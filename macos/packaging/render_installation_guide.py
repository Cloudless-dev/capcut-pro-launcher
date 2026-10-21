"""Render the bilingual installation guide with ReportLab and Noto Sans fonts.

Usage: python render_installation_guide.py --font-dir /path/to/noto/fonts
Illustrations are vectors and contain no screenshots or local account data.
"""
import argparse
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parents[1]
INK = colors.HexColor('#182237')
MUTED = colors.HexColor('#59677d')
BLUE = colors.HexColor('#4267e9')
W, H = A4
MARGIN = 42
WIDTH = W - 2 * MARGIN


def paragraph(c, value, y, size=10.5, color=MUTED):
    style = ParagraphStyle('body', fontName='Noto', fontSize=size,
                           leading=size * 1.48, textColor=color)
    p = Paragraph(value, style)
    _, height = p.wrap(WIDTH, H)
    p.drawOn(c, MARGIN, y - height)
    return y - height


def heading(c, number, title, y):
    c.setFillColor(BLUE)
    c.roundRect(MARGIN, y - 5, 24, 24, 7, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont('NotoBold', 11)
    c.drawCentredString(MARGIN + 12, y + 2, str(number))
    c.setFillColor(INK)
    c.setFont('NotoBold', 13)
    c.drawString(MARGIN + 36, y + 1, title)


def panel(c, y, title, button):
    c.setFillColor(colors.HexColor('#f1f4f9'))
    c.roundRect(MARGIN, y, WIDTH, 83, 12, fill=1, stroke=0)
    c.setFillColor(MUTED)
    c.setFont('Noto', 9)
    c.drawString(MARGIN + 17, y + 61, title)
    c.setStrokeColor(colors.HexColor('#dce2ed'))
    c.line(MARGIN + 17, y + 49, W - MARGIN - 17, y + 49)
    c.setFillColor(INK)
    c.setFont('NotoBold', 11)
    c.drawString(MARGIN + 17, y + 22, 'CapCut Launcher.app')
    width = max(118, pdfmetrics.stringWidth(button, 'NotoBold', 10) + 24)
    x = W - MARGIN - 17 - width
    c.setFillColor(BLUE)
    c.roundRect(x, y + 16, width, 28, 7, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont('NotoBold', 10)
    c.drawCentredString(x + width / 2, y + 25, button)


def app_management(c, y, en):
    """A privacy-safe illustration matching the macOS Settings controls."""
    c.setFillColor(colors.HexColor('#f5f5f5'))
    c.roundRect(MARGIN, y, WIDTH, 100, 10, fill=1, stroke=0)
    c.setFillColor(colors.HexColor('#e9e9e9'))
    c.roundRect(MARGIN + 10, y + 74, 40, 20, 10, fill=1, stroke=0)
    c.setStrokeColor(colors.HexColor('#686868'))
    c.setLineWidth(1.3)
    p = c.beginPath()
    p.moveTo(MARGIN + 24, y + 89); p.lineTo(MARGIN + 19, y + 84); p.lineTo(MARGIN + 24, y + 79)
    c.drawPath(p)
    c.setStrokeColor(colors.HexColor('#b7b7b7'))
    p = c.beginPath()
    p.moveTo(MARGIN + 34, y + 89); p.lineTo(MARGIN + 39, y + 84); p.lineTo(MARGIN + 34, y + 79)
    c.drawPath(p)
    c.setFillColor(colors.HexColor('#282828'))
    c.setFont('NotoBold', 11)
    c.drawString(MARGIN + 60, y + 81, 'App Management' if en else 'Управление приложениями')
    c.setFillColor(colors.white)
    c.roundRect(MARGIN + 10, y + 7, WIDTH - 20, 61, 8, fill=1, stroke=0)
    c.setFillColor(colors.HexColor('#777777'))
    c.setFont('Noto', 8)
    c.drawString(MARGIN + 20, y + 54, 'Allow the applications below to update or delete other applications.' if en else
                 'Разрешить этим приложениям обновлять или удалять другие приложения.')
    c.setStrokeColor(colors.HexColor('#e5e5e5'))
    c.setLineWidth(.5)
    c.line(MARGIN + 10, y + 45, W - MARGIN - 10, y + 45)
    c.drawImage(str(ROOT / 'packaging/assets/launcher.png'), MARGIN + 20, y + 20,
                width=21, height=21, mask='auto')
    c.setFillColor(colors.HexColor('#282828'))
    c.setFont('Noto', 10)
    c.drawString(MARGIN + 51, y + 27, 'CapCut Launcher.app')
    x = W - MARGIN - 62
    c.setFillColor(colors.HexColor('#3478f6'))
    c.roundRect(x, y + 22, 35, 20, 10, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.circle(x + 25, y + 32, 8, fill=1, stroke=0)
    c.setStrokeColor(colors.HexColor('#a0a0a0'))
    c.setLineWidth(.9)
    c.line(MARGIN + 20, y + 13, MARGIN + 26, y + 13)
    c.line(MARGIN + 23, y + 10, MARGIN + 23, y + 16)
    c.line(MARGIN + 35, y + 13, MARGIN + 41, y + 13)


def page(c, en):
    c.setFillColor(BLUE)
    c.setFont('NotoBold', 10)
    c.drawString(MARGIN, 800, 'CAPCUT LAUNCHER')
    c.setFillColor(MUTED)
    c.setFont('Noto', 9)
    c.drawRightString(W - MARGIN, 800, 'ENGLISH  /  2' if en else 'РУССКИЙ  /  1')
    c.setFillColor(INK)
    c.setFont('NotoBold', 26)
    c.drawString(MARGIN, 759, 'Install & get started' if en else 'Установка и первый запуск')
    paragraph(c, 'macOS 14+ · Apple Silicon (M-series)' if en else
              'macOS 14+ · Apple Silicon (M-серия)', 737, 10)

    heading(c, 1, 'Move the app to Applications' if en else 'Перенесите приложение в «Программы»', 693)
    paragraph(c, 'Open the DMG. Drag CapCut Launcher to Applications. Open the copy in Applications. '
              'Install the official CapCut from its website before using the launcher.' if en else
              'Откройте DMG. Перетащите CapCut Launcher в «Программы» и запускайте копию оттуда. '
              'Для работы нужен официальный CapCut с сайта производителя.', 673)

    heading(c, 2, 'Allow the first launch if macOS blocks it' if en else 'Разрешите первый запуск, если macOS блокирует его', 612)
    paragraph(c, 'Try opening the app once. Then go to System Settings / Privacy &amp; Security / '
              '<b>Open Anyway</b>. Confirm using your Mac password or Touch ID, then open the app.' if en else
              'Сначала попробуйте открыть приложение. Затем: Системные настройки / '
              'Конфиденциальность и безопасность / <b>Всё равно открыть</b>. '
              'Подтвердите паролем Mac или Touch ID и откройте приложение.', 592)
    panel(c, 445, 'Privacy & Security' if en else 'Конфиденциальность и безопасность',
          'Open Anyway' if en else 'Всё равно открыть')

    heading(c, 3, 'Enable App Management' if en else 'Включите «Управление приложениями»', 413)
    paragraph(c, 'Before launching CapCut through the launcher, open System Settings / Privacy &amp; '
              'Security / <b>App Management</b>. Enable the switch for CapCut Launcher.' if en else
              'До запуска CapCut через лаунчер откройте Системные настройки / '
              'Конфиденциальность и безопасность / <b>Управление приложениями</b>. '
              'Включите CapCut Launcher.', 393)
    app_management(c, 236, en)
    paragraph(c, 'Not listed? Click <b>+</b> and select Applications / CapCut Launcher.app. '
              'This permission allows an app to update or delete other applications.' if en else
              'Нет в списке? Нажмите <b>+</b> и выберите «Программы» / CapCut Launcher.app. '
              'Это разрешение позволяет приложению обновлять или удалять другие приложения.', 223, 9.5)

    heading(c, 4, 'Restart, then sign in' if en else 'Перезапустите и войдите в профиль', 167)
    paragraph(c, 'Fully quit CapCut and the launcher after changing permissions. Reopen the launcher, '
              'create a profile, sign in through its browser and choose a region. If CapCut asks '
              'for access to your media, allow access to the folder you use.' if en else
              'После выдачи разрешения полностью закройте CapCut и лаунчер. Откройте лаунчер снова, '
              'создайте профиль, войдите через браузер и выберите регион. Если CapCut запросит '
              'доступ к медиа, разрешите доступ к нужной папке.', 147)

    c.setStrokeColor(colors.HexColor('#dce2ed'))
    c.line(MARGIN, 74, W - MARGIN, 74)
    paragraph(c, 'Illustrations show the controls schematically. Labels may vary by macOS version.' if en else
              'Иллюстрации схематичные. Названия пунктов могут отличаться в разных версиях macOS.', 63, 8)
    c.setFillColor(MUTED)
    c.setFont('Noto', 8)
    label = 'Apple: opening downloaded apps · Privacy & Security' if en else 'Apple: открытие приложений · Конфиденциальность и безопасность'
    c.drawString(MARGIN, 31, label)
    c.linkURL('https://support.apple.com/102445', (MARGIN, 28, MARGIN + 180, 43), relative=0)
    c.linkURL('https://support.apple.com/guide/mac-help/mchl211c911f/mac',
              (MARGIN + 180, 28, W - MARGIN, 43), relative=0)
    c.showPage()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'packaging/assets/Installation.pdf')
    args = parser.parse_args()
    for name, filename in [('Noto', 'NotoSans-Regular.ttf'), ('NotoBold', 'NotoSans-Bold.ttf')]:
        pdfmetrics.registerFont(TTFont(name, str(args.font_dir / filename)))
    pdfmetrics.registerFontFamily('Noto', normal='Noto', bold='NotoBold')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(args.output), pagesize=A4, invariant=1)
    c.setTitle('CapCut Launcher | Installation / Установка')
    c.setAuthor('CapCut Launcher')
    c.setSubject('Installation and macOS permissions. Russian / English.')
    page(c, False)
    page(c, True)
    c.save()
    print(args.output)


if __name__ == '__main__':
    main()
