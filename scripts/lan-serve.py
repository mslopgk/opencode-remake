# -*- coding: utf-8 -*-
"""현장에서 설치에 필요한 것을 내부망으로 뿌린다.

왜 필요한가 (2026-09-05, 행사장):
  들어오는 회선이 100Mbps 인데 학생 60여 명이 375MB 를 한꺼번에 받으면
  22GB 를 100Mbps 로 빨아들이는 셈이라 회선이 죽는다.
  내부망은 1Gbps + 5GHz 라서, 진행자 노트북에서 뿌리면 훨씬 빠르고
  바깥 회선을 전혀 안 쓴다.

무엇을 하는가:
  - 폴더 하나를 통째로 뿌린다 (윈도우 설치 파일 + 맥 몫)
  - 스레드 방식으로 여러 명에게 동시에 보낸다
  - Range 를 지원한다. 와이파이가 끊겨도 브라우저가 이어받는다
  - 표딱지(ETag)를 붙인다. 파일을 바꿔도 이어받기가 섞이지 않는다
  - 누가 얼마나 받았는지 화면에 보여 준다

쓰는 법:
  python lan-serve.py <뿌릴폴더> [포트]
"""
import hashlib
import os
import posixpath
import socket
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

뿌릴곳 = sys.argv[1] if len(sys.argv) > 1 else 'lan-share'
포트 = int(sys.argv[2]) if len(sys.argv) > 2 else 80

if not os.path.isdir(뿌릴곳):
    print('폴더가 없어요: ' + 뿌릴곳)
    sys.exit(1)

뿌릴곳 = os.path.abspath(뿌릴곳)

# 브라우저가 저장할 이름. 한글은 RFC 5987 로 적는다.
설치이름 = ("attachment; filename=camp2026-setup.exe; "
            "filename*=UTF-8''%EC%B0%BD%EC%9D%98%EB%94%94%EC%9E%90%EC%9D%B8"
            "%EC%BA%A0%ED%94%84%20%EC%84%A4%EC%B9%98.exe")


def 훑기(뿌리):
    """폴더 안의 파일을 모두 찾아 표딱지를 붙인다."""
    모음 = {}
    for 방, _, 파일목록 in os.walk(뿌리):
        for 이름 in 파일목록:
            전체 = os.path.join(방, 이름)
            상대 = os.path.relpath(전체, 뿌리).replace(os.sep, '/')
            크기 = os.path.getsize(전체)
            h = hashlib.sha256()
            with open(전체, 'rb') as f:
                while True:
                    조각 = f.read(1 << 22)
                    if not 조각:
                        break
                    h.update(조각)
            모음['/' + 상대] = {
                '경로': 전체,
                '크기': 크기,
                '표딱지': '"' + h.hexdigest()[:16] + '-' + str(크기) + '"',
                '해시': h.hexdigest(),
            }
    return 모음


print('파일을 훑고 표딱지를 붙이는 중...')
파일들 = 훑기(뿌릴곳)
if not 파일들:
    print('뿌릴 파일이 없어요: ' + 뿌릴곳)
    sys.exit(1)

# 윈도우 설치 파일을 찾는다. /setup.exe 로도 받을 수 있게 한다.
설치파일 = None
for 길 in sorted(파일들):
    바닥 = posixpath.basename(길).lower()
    if 바닥.startswith('camp2026-setup') and 바닥.endswith('.exe'):
        설치파일 = 길
        break

for 길 in sorted(파일들):
    ㅈ = 파일들[길]
    print('  {:<40} {:>8.1f} MB  {}'.format(
        길, ㅈ['크기'] / 1048576, ㅈ['해시'][:16]))
if 설치파일:
    print('  설치 파일: ' + 설치파일 + '  (/setup.exe 로도 받아져요)')

상태 = {'시작': 0, '끝': 0, '보낸바이트': 0}
잠금 = threading.Lock()
시작시각 = time.time()


def 내주소():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'


IP = 내주소()
주소 = 'http://' + IP + ('' if 포트 == 80 else ':' + str(포트))
맥설치 = 'curl -fsSL ' + 주소 + '/mac -o ~/camp.sh && bash ~/camp.sh'
맥점검 = 'curl -fsSL ' + 주소 + '/check -o ~/check.sh && bash ~/check.sh'
맥지우기 = 'curl -fsSL ' + 주소 + '/uninstall -o ~/del.sh && bash ~/del.sh'
맥고치기 = 'curl -fsSL ' + 주소 + '/mac-fix -o ~/fix.sh && bash ~/fix.sh'
맥한줄 = 맥설치

안내틀 = """<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>창의디자인캠프 설치</title>
<style>
 body{margin:0;font-family:'Malgun Gothic',system-ui,sans-serif;
      background:#0f172a;color:#f8fafc;display:flex;min-height:100vh;
      align-items:center;justify-content:center;text-align:center}
 .box{padding:32px;max-width:660px}
 h1{font-size:34px;margin:0 0 8px}
 p{font-size:19px;color:#cbd5e1;margin:0 0 28px;line-height:1.6}
 a.btn{display:inline-block;background:#38bdf8;color:#0f172a;font-size:26px;
       font-weight:700;text-decoration:none;padding:22px 46px;border-radius:16px}
 a.btn:active{background:#0ea5e9}
 .fix{margin-top:30px;padding:18px;border:1px solid #f59e0b;border-radius:14px;
      font-size:17px;color:#fcd34d;line-height:1.7}
 .fix b{color:#fde68a}
 a.btn2{display:inline-block;margin-top:12px;background:#f59e0b;color:#1c1917;
        font-size:19px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:12px}
 a.btn2:active{background:#d97706}
 .tip{margin-top:26px;font-size:16px;color:#94a3b8;line-height:1.7}
 .tip b{color:#f8fafc}
 .mac{margin-top:38px;padding-top:26px;border-top:1px solid #334155;
      font-size:16px;color:#94a3b8;line-height:1.7}
 .mac b{color:#e2e8f0}
 .lbl{margin-top:18px;color:#e2e8f0;font-weight:700;text-align:left}
 .warn{margin-top:14px;font-size:14px;color:#fbbf24;text-align:left}
 code{display:block;margin-top:6px;padding:14px 16px;background:#1e293b;
      color:#7dd3fc;border-radius:10px;font-size:15px;word-break:break-all;
      text-align:left;user-select:all}
</style>
<div class="box">
<h1>창의디자인캠프 설치 파일</h1>
<p>아래 큰 단추를 누르면 받아져요.<br>다 받으면 그 파일을 두 번 눌러 주세요.</p>
<a class="btn" href="/setup.exe">설치 파일 받기</a>
<div class="fix"><b>이미 설치했는데 영상이 안 만들어지면</b><br>
아래 것만 받아서 두 번 누르세요. 20KB 라 금방 끝나요.<br>
<a class="btn2" href="/%EB%8F%84%EA%B5%AC%20%EA%B3%A0%EC%B9%98%EA%B8%B0.exe">도구 고치기</a></div>
<div class="tip">받는 데 좀 걸려요. 중간에 멈춘 것처럼 보여도 기다려 주세요.<br>
끊기면 이 화면에서 다시 눌러도 이어서 받아져요.<br>
설치를 시작할 때 <b>"이 앱이 변경하도록 허용할까요?"</b> 가 뜨면 <b>예</b>를 눌러 주세요.</div>
<div class="mac"><b>맥(MacBook)을 쓰면</b> 위 단추 말고 이렇게 해요.<br>
런치패드에서 <b>터미널</b>을 열고, 아래 줄을 그대로 붙여넣고 엔터를 누르세요.
<div class="lbl">설치하기</div><code>__MAC__</code>
<div class="lbl">이미 설치했으면 — 도구 고치기 (제일 먼저 이것)</div><code>__MACFIX__</code>
<div class="lbl">잘 되는지 확인하기</div><code>__MACCHECK__</code>
<div class="lbl">지우고 처음부터 다시 하기</div><code>__MACDEL__</code>
<div class="warn">지우기는 학생이 만든 작품은 그대로 두고, 캠프가 넣은 것만 지웁니다.</div>
</div>
<div class="mac"><b>아주 오래된 윈도우(10 버전 1703)</b>를 쓰면 위 단추 대신
<a href="/old/win1703-setup.exe" style="color:#7dd3fc">이 파일</a>을 받으세요.<br>
선생님이 따로 알려준 학생만 쓰면 됩니다.</div>
</div></html>"""
안내바이트 = (안내틀.replace('__MAC__', 맥설치)
                      .replace('__MACCHECK__', 맥점검)
                      .replace('__MACFIX__', 맥고치기)
                      .replace('__MACDEL__', 맥지우기)).encode('utf-8')


def 맥글(이름='/mac-install.sh'):
    """맥 글에 우리 주소를 박아서 돌려준다.

    파일을 텍스트로 여는 것이 중요하다. 윈도우에서 만든 파일에 CRLF 가
    남아 있어도 여기서 LF 로 바뀐다. 'rb' 로 바꾸면 맥에서 전부 깨진다
    (실측 사고: 경로 끝에 
 이 붙어 설정과 열쇠가 엉뚱한 폴더로 갔다).
    """
    ㅈ = 파일들.get(이름)
    if ㅈ is None:
        return '그 글이 없어요: ' + 이름 + chr(10)
    with open(ㅈ['경로'], encoding='utf-8') as f:
        글 = f.read()
    return 글.replace('__CAMP_SERVER__', 주소)


class 손(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'CampLAN/2.0'

    # HTTP/1.1 은 연결을 계속 열어 둔다. 그런데 파이썬 기본값은 타임아웃이
    # 없어서, 학생이 노트북 덮개를 닫으면 그 스레드가 영영 안 죽는다(실측:
    # 유휴 40개를 만들었더니 20초 뒤에도 스레드 42개가 그대로였다).
    # 60명이 오가면 스레드가 수백 개로 쌓인다.
    #
    # 120초로 잡는 이유: 이 값은 보내기에도 걸린다. 256KB 한 덩이는 아주
    # 느린 학생도 몇 초면 받는다. 30초처럼 짧게 잡으면 느린 학생을 끊는다.
    timeout = 120

    def log_message(self, *a):
        pass          # 기본 로그는 시끄럽다. 우리가 따로 찍는다.

    def log_error(self, *a):
        pass          # 끊긴 연결마다 빨간 글씨가 뜨면 진짜 상태가 묻힌다.

    def do_HEAD(self):
        self.보내기(True)

    def do_GET(self):
        self.보내기(False)

    def 짧게(self, 코드):
        self.send_response(코드)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def 보내기(self, 머리만):
        # 브라우저는 한글을 %XX 로 바꿔 보내지만, curl 은 날것 그대로 보낸다.
        # 파이썬 http.server 는 요청 줄을 latin-1 로 읽으므로 그대로 두면
        # 한글 주소가 전부 404 가 된다. 한 번 되돌려 놓고 본다.
        원길 = self.path.split('?')[0]
        try:
            원길 = 원길.encode('latin-1').decode('utf-8')
        except Exception:
            pass
        길 = urllib.parse.unquote(원길)

        if 길 in ('/', '/index.html'):
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(안내바이트)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            if not 머리만:
                self.wfile.write(안내바이트)
            return

        # 맥 설치 글은 터미널이 읽는다. 브라우저로 열어도 글자로 보이게 한다.
        #
        # 그리고 "어느 서버에서 받아라" 를 우리가 직접 써 넣어 준다.
        # 포트를 바꿔도 학생이 고칠 것이 없다.
        맥길 = None
        if 길 in ('/mac', '/mac.sh', '/mac-install.sh'):
            맥길 = '/mac-install.sh'
        elif 길 in ('/check', '/점검', '/mac-check.sh'):
            맥길 = '/mac-check.sh'
        elif 길 in ('/uninstall', '/지우기', '/삭제', '/mac-uninstall.sh'):
            맥길 = '/mac-uninstall.sh'
        elif 길 in ('/mac-fix', '/fix', '/고치기', '/mac-fix.sh'):
            맥길 = '/mac-fix.sh'
        if 맥길 is not None:
            글 = 맥글(맥길).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(글)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            if not 머리만:
                self.wfile.write(글)
            return
        글자로 = False

        if 길 in ('/setup.exe', '/camp2026-setup.exe') and 설치파일:
            길 = 설치파일
        설치냐 = (길 == 설치파일)

        ㅈ = 파일들.get(길)
        if ㅈ is None:
            self.짧게(404)
            return

        크기 = ㅈ['크기']
        표딱지 = ㅈ['표딱지']

        # Range: 와이파이가 끊겨도 브라우저가 이어받게 한다.
        #
        # 표딱지가 다르면 이어받기를 거절하고 처음부터 준다.
        # 받는 도중에 우리가 파일을 새 것으로 바꾸면 앞뒤가 섞인 exe 가
        # 만들어진다. 학생은 그게 깨진 줄 모른 채 두 번 누른다(실측 위험).
        처음, 끝 = 0, 크기 - 1
        범위 = self.headers.get('Range')
        조건 = self.headers.get('If-Range')
        if 조건 is not None and 조건.strip() != 표딱지:
            범위 = None
        부분 = False
        if 범위 and 범위.startswith('bytes='):
            try:
                a, _, b = 범위[6:].partition('-')
                if a:
                    처음 = int(a)
                    if b:
                        끝 = int(b)
                else:
                    처음 = 크기 - int(b)
                if 처음 < 0 or 처음 >= 크기 or 끝 >= 크기 or 처음 > 끝:
                    raise ValueError
                부분 = True
            except Exception:
                self.send_response(416)
                self.send_header('Content-Range', 'bytes */' + str(크기))
                self.send_header('Content-Length', '0')
                self.end_headers()
                return

        보낼길이 = 끝 - 처음 + 1
        self.send_response(206 if 부분 else 200)
        if 글자로:
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
        else:
            self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(보낼길이))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('ETag', 표딱지)
        if 설치냐:
            self.send_header('Content-Disposition', 설치이름)
        if 부분:
            self.send_header('Content-Range',
                             'bytes {}-{}/{}'.format(처음, 끝, 크기))
        self.end_headers()
        if 머리만:
            return

        # 작은 파일까지 일일이 세면 화면이 시끄럽다. 큰 것만 센다.
        셀것 = (크기 > 10 * 1048576)
        번호 = 0
        누구 = self.client_address[0]
        if 셀것:
            with 잠금:
                상태['시작'] += 1
                번호 = 상태['시작']
            print('  #{:<3} 받기 시작: {}  {}{}'.format(
                번호, 누구, posixpath.basename(길),
                '  (이어받기)' if 부분 else ''))

        보낸 = 0
        try:
            with open(ㅈ['경로'], 'rb') as f:
                f.seek(처음)
                남음 = 보낼길이
                while 남음 > 0:
                    조각 = f.read(min(1 << 18, 남음))
                    if not 조각:
                        break
                    self.wfile.write(조각)
                    남음 -= len(조각)
                    보낸 += len(조각)
            with 잠금:
                상태['보낸바이트'] += 보낸
                if 셀것:
                    상태['끝'] += 1
                끝난수, 시작수 = 상태['끝'], 상태['시작']
            if 셀것:
                print('  #{:<3} 다 받음   {}   (완료 {}건 / 시작 {}건)'.format(
                    번호, 누구, 끝난수, 시작수))
        except Exception:
            with 잠금:
                상태['보낸바이트'] += 보낸
            if 셀것:
                print('  #{:<3} 끊김     {}  {:.0f}% 에서 (다시 누르면 이어받아요)'
                      .format(번호, 누구, 100.0 * 보낸 / max(보낼길이, 1)))


class 서버(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 128

    def handle_error(self, request, client_address):
        # 학생이 받다 말고 끊으면 예외가 난다. 정상적인 일이다.
        # 기본 동작은 통째로 트레이스백을 찍는데, 60명이 오가면
        # 진행자 화면이 그걸로 도배돼서 진짜 상태 줄이 안 보인다.
        pass


def 알림():
    while True:
        time.sleep(20)
        with 잠금:
            ㄱ, ㄲ, ㅂ = 상태['시작'], 상태['끝'], 상태['보낸바이트']
        if ㄱ == 0:
            continue
        걸린 = max(time.time() - 시작시각, 1)
        print('[현황] 시작 {}건 / 완료 {}건 / 보낸 양 {:.1f} GB / 평균 {:.0f} Mbps'
              .format(ㄱ, ㄲ, ㅂ / 1073741824, ㅂ * 8 / 걸린 / 1e6))


if __name__ == '__main__':
    threading.Thread(target=알림, daemon=True).start()
    s = 서버(('0.0.0.0', 포트), 손)
    print('')
    print('=' * 54)
    print('  학생들에게 이 주소를 알려 주세요')
    print('     ' + 주소)
    print('')
    print('  맥을 쓰는 학생은 터미널에 이 한 줄')
    print('     ' + 맥한줄)
    print('=' * 54)
    print('  멈추려면 이 창에서 Ctrl+C')
    print('')
    try:
        s.serve_forever()
    except KeyboardInterrupt:
        print('멈췄습니다.')
