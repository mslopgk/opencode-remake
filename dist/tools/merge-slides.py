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
    for f in files:
        body = io.open(f, encoding='utf-8').read()
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
    sys.exit(main())
