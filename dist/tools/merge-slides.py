# 친구들이 각자 만든 slides/*.html 을 index.html 하나로 합친다.
#
# 왜 별도 파일인가: 원래 merge-slides.sh 안에서 `python - <<'PY'` 로 넘겼는데,
# opencode 의 bash 툴에서 실행하면 python 이 stdin 을 기다리며 멈췄다
# (실측: 10분 초과). 에이전트가 실행하는 스크립트는 stdin 을 읽으면 안 된다.
#
# 사용법: python merge-slides.py <팀폴더>
# 출력: 합친 장 수 (숫자 한 줄)
# 종료코드: 0=성공, 4=인자/경로 오류, 5=조립 지점 없음

import glob
import io
import os
import re
import sys

MARK_BEGIN = '<!-- 여기에 친구들 슬라이드가 들어갑니다 (합쳐줘 를 쓰면 아래에 채워져요) -->'
MARK_END = '<!-- 친구들 슬라이드 끝 -->'


def 읽기(경로):
    """어떤 인코딩으로 저장했든 읽어 본다. 못 읽으면 None."""
    with open(경로, 'rb') as f:
        raw = f.read()
    for enc in ('utf-8-sig', 'utf-8', 'cp949'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            pass
    return None


def main():
    if len(sys.argv) < 2:
        sys.stderr.write('팀 폴더가 필요해요.\n')
        return 4

    team = sys.argv[1]
    if not os.path.isdir(team):
        sys.stderr.write('팀 폴더를 찾을 수 없어요.\n')
        return 4

    index_path = os.path.join(team, 'index.html')
    if not os.path.isfile(index_path):
        sys.stderr.write('발표자료를 찾을 수 없어요.\n')
        return 4

    html = io.open(index_path, encoding='utf-8').read()
    if MARK_BEGIN not in html:
        sys.stderr.write('발표자료에 합치는 자리가 없어요.\n')
        return 5

    # 이전에 합친 구간을 먼저 걷어낸다 (중복 누적 방지)
    start = html.find(MARK_BEGIN)
    end = html.find(MARK_END)
    if end != -1:
        html = html[:start + len(MARK_BEGIN)] + html[end + len(MARK_END):]

    # slides/*.html 을 파일명 순으로 모은다
    files = sorted(glob.glob(os.path.join(team, 'slides', '*.html')))
    sections = []
    건너뜀 = 0
    for f in files:
        # 친구가 메모장으로 저장하면 cp949 로 저장된다. 그 한 장 때문에
        # 나머지 세 명 슬라이드까지 통째로 못 합치면 안 된다(실측 확인).
        body = 읽기(f)
        if body is None:
            건너뜀 += 1
            continue
        found = re.findall(r'<section\b[^>]*>.*?</section>', body, re.S)
        if found:
            sections.extend(found)
        else:
            # section 태그가 없으면 통째로 한 장으로 감싼다
            stripped = body.strip()
            if stripped:
                sections.append('<section class="slide">\n' + stripped + '\n</section>')

    if not sections:
        sys.stdout.write('0\n')
        return 0

    block = '\n' + '\n\n'.join(sections) + '\n' + MARK_END + '\n'
    start = html.find(MARK_BEGIN)
    html = html[:start + len(MARK_BEGIN)] + block + html[start + len(MARK_BEGIN):]

    io.open(index_path, 'w', encoding='utf-8', newline='\n').write(html)
    sys.stdout.write(str(len(sections)) + '\n')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        # 영어 트레이스백과 파일 경로가 학생 화면에 나오면 안 된다.
        sys.stderr.write('합치는 데 문제가 생겼어요. 선생님을 불러 주세요.' + chr(10))
        sys.exit(5)
