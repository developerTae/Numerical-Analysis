clearvars; % 작업 공간 지우기

fin=fopen('./lena(256x256)_3.raw','r'); % downsampled 영상(256x256) 읽기
down=fread(fin, [256 256]);
fclose(fin);

H = [0 -1 0; 0 2 0;0 -1 0]; % 라플라시안 마스크
V = [0 0 0; -1 2 -1; 0 0 0];
D135 = [-1 0 0; 0 2 0; 0 0 -1];
D45 = [0 0 -1; 0 2 0; -1 0 0];

% Pixel Classification (블럭 1개에 픽셀 4개)
act = zeros(1,4096); % 각 블럭의 활동성 저장
dirOfBlock = zeros(1,4096); % 각 블럭의 방향성 저장
for i = 1:4:256 % 행
    for j = 1:4:256 % 열
        block = down(i:i+3,j:j+3); % 4x4
        h = abs(sum(block(1:3,1:3).*H, 'all')) + abs(sum(block(2:4,1:3).*H, 'all')) + abs(sum(block(1:3,2:4).*H, 'all')) + abs(sum(block(2:4,2:4).*H, 'all'));
        v = abs(sum(block(1:3,1:3).*V, 'all')) + abs(sum(block(2:4,1:3).*V, 'all')) + abs(sum(block(1:3,2:4).*V, 'all')) + abs(sum(block(2:4,2:4).*V, 'all'));
        d135 = abs(sum(block(1:3,1:3).*D135, 'all')) + abs(sum(block(2:4,1:3).*D135, 'all')) + abs(sum(block(1:3,2:4).*D135, 'all')) + abs(sum(block(2:4,2:4).*D135, 'all'));
        d45 = abs(sum(block(1:3,1:3).*D45, 'all')) + abs(sum(block(2:4,1:3).*D45, 'all')) + abs(sum(block(1:3,2:4).*D45, 'all')) + abs(sum(block(2:4,2:4).*D45, 'all'));
        
        [M, I] = max([10 h v d135 d45]); % 방향성 결정
        dirOfBlock(64*((i+3)/4 - 1)+(j+3)/4) = I;
        
        act(64*((i+3)/4 - 1)+(j+3)/4) = h + v + d135 + d45; % 각 블럭의 활동성 저장
    end
end
actOfBlock = fix(act/(round(max(act)/5)+1)); % 활동성 맵핑 (양자화)
classOfBlocks = actOfBlock*5 + (dirOfBlock - 1); % 각 블럭의 클래스 정보 저장

fin2=fopen('./lena(512x512).raw','r'); % 원본 영상(512x512) 읽기
ori=fread(fin2, [512 512]);
fclose(fin2);
up = imresize(down, 2, 'box');

% 적응형 보간 필터
wc_h = zeros(4,100); % 각 클래스별 optimized horizontal filter
wc_v = zeros(4,100); % 각 클래스별 optimized vertical filter
for i = 1:8:512 % 행
    for j = 1:8:512 % 열
        for k = 1:2:8
            x_h = up(i+(k-1), [j j+2 j+4 j+6]);
            x_v = up(j+(k-1), [i i+2 i+4 i+6]);
            y_h = ori(i+(k-1), [j+1 j+3 j+5 j+7]);
            y_v = ori(j+(k-1), [i+1 i+3 i+5 i+7]);
            wc_h_tmp = pinv(x_h.'*x_h)*x_h.'*y_h;
            wc_v_tmp = pinv(x_v.'*x_v)*x_v.'*y_v;
            c = classOfBlocks(64*((i+7)/8 - 1)+(j+7)/8);
            wc_h(1:4,1+4*c:4+4*c) =  wc_h(1:4,1+4*c:4+4*c) + wc_h_tmp;
            wc_v(1:4,1+4*c:4+4*c) =  wc_v(1:4,1+4*c:4+4*c) + wc_v_tmp;
        end
    end
end

for i =1:1:25
    cnt = sum(classOfBlocks==i);
    if cnt == 0
        cnt = 1;
    end
    wc_h(1:4,1+4*(i-1):4+4*(i-1)) =  wc_h(1:4,1+4*(i-1):4+4*(i-1))/cnt;
    wc_v(1:4,1+4*(i-1):4+4*(i-1)) =  wc_v(1:4,1+4*(i-1):4+4*(i-1))/cnt;
end

% 적응형 보간 필터 적용
aif = up;
for i = 1:8:512 % 행
    for j = 1:8:512 % 열
        c = classOfBlocks(64*((i+7)/8 - 1)+(j+7)/8);
        for k = 1:2:8 % 수평 방향
            aif(i+(k-1),[j+1 j+3 j+5 j+7]) = aif(i+(k-1),[j j+2 j+4 j+6])*wc_h(1:4,1+4*c:4+4*c);
        end
        for l = 1:1:8 % 수직 방향
            temp = aif([i i+2 i+4 i+6], j+(l-1)).'*wc_v(1:4,1+4*c:4+4*c);
            aif([i+1 i+3 i+5 i+7], j+(l-1)) = temp.';
        end
    end
end

fout = fopen('./AIF_lena(512x512).raw', 'wb'); % AIF 필터로 보간된 영상 저장
fwrite(fout, aif);
fclose(fout);

% 6-tap 필터 적용
tap = up;
padded = padarray(tap,[4,4],'replicate');
sinc = [11 -43 160 160 -43 11];
for i = 1:8:512 % 행
    for j = 1:8:512 % 열
        for k = 1:2:8 % 수평방향(half-pel)
            padded(k+i+3, j+5) = round((padded(i+k+3, [j j+2 j+4 j+6 j+8 j+10])*sinc.')/256);
        end
        for l = 1:1:8 % 수직방향(half-pel)
            padded(i+5, j+l+3) = round((padded([i i+2 i+4 i+6 i+8 i+10], j+l+3).'*sinc.')/256);
        end
    end
end
tap = padded(5:516,5:516);

fout=fopen('./6-tap_lena(512x512).raw', 'wb'); % 6-tap 필터로 보간된 영상 저장
fwrite(fout, tap);
fclose(fout);

% PSNR
N = 512*512;
sum = 0;
for i = 1:1:512
    for j = 1:1:512
        error = ori(i,j)-tap(i,j);
        sum = sum + error*error;
    end
end
mse = sum/N;
psnr = 20*log10(255/sqrt(mse));

psnr
