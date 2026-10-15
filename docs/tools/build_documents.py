"""Build current Markdown manuals as Unicode PDFs; optional render for visual QA.

Run with the bundled Python: build_documents.py --render
Requires reportlab, pypdf, pypdfium2 and Pillow. Does not modify runtime sources.
"""
from pathlib import Path
import argparse
import html
import os
import re
import textwrap
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image,
    PageBreak, KeepTogether, Preformatted,
)

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs'
DOCSETS = [
    ('KULLANIM_KILAVUZU.md', ROOT / 'KULLANIM_KILAVUZU.pdf', 'Kullanım kılavuzu'),
    ('TEKNIK_EL_KITABI.md', DOCS / 'RemoteOps_Teknik_El_Kitabi.pdf', 'Teknik el kitabı'),
    ('CALISMA_MANTIGI.md', DOCS / 'RemoteOps_Calisma_Mantigi.pdf', 'Çalışma mantığı'),
    ('INCELEME_RAPORU.md', DOCS / 'RemoteOps_Inceleme_Raporu.pdf', 'İnceleme raporu'),
    ('GELECEK_OPERASYON_OLUSTUR.md', DOCS / 'RemoteOps_Operasyon_Olustur_Tasarim.pdf', 'Reçeteler ve gelecek geliştirmeler'),
]
FONTDIR = Path('C:/Windows/Fonts')
for name, filename in [('UI', 'segoeui.ttf'), ('UIBold', 'segoeuib.ttf'), ('Code', 'consola.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(FONTDIR / filename)))
pdfmetrics.registerFontFamily('UI', normal='UI', bold='UIBold', italic='UI', boldItalic='UIBold')
INK = colors.HexColor('#1F3342')
TEAL = colors.HexColor('#087F87')
WIDTH = 174 * mm
STYLES = {
    'body': ParagraphStyle('Body', fontName='UI', fontSize=10, leading=13.5,
                           textColor=INK, spaceAfter=6.5, splitLongWords=True,
                           allowOrphans=0, allowWidows=0),
    'h2': ParagraphStyle('H2', fontName='UIBold', fontSize=14, leading=19,
                         textColor=TEAL, spaceBefore=14, spaceAfter=8, keepWithNext=True),
    'title': ParagraphStyle('Title', fontName='UIBold', fontSize=30, leading=38,
                            textColor=INK, spaceAfter=20),
    'small': ParagraphStyle('Small', fontName='UI', fontSize=8.5, leading=12,
                            textColor=colors.HexColor('#556B7B'), spaceAfter=8),
    'cell': ParagraphStyle('Cell', fontName='UI', fontSize=8, leading=11,
                           textColor=INK, splitLongWords=True),
    'headcell': ParagraphStyle('HeadCell', fontName='UIBold', fontSize=8, leading=11,
                               textColor=colors.white, splitLongWords=True),
    'code': ParagraphStyle('Code', fontName='Code', fontSize=7.5, leading=10.5,
                           textColor=INK, backColor=colors.HexColor('#EFF4F8'),
                           borderPadding=8, spaceBefore=3, spaceAfter=12),
}

def inline(text):
    text = html.escape(text)
    # Local document links remain descriptive labels. Full clickable targets are
    # in Markdown; relative file links inside PDF are unreliable after sharing.
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'\1', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'`([^`]+)`', r'<font name="Code">\1</font>', text)
    return text

def para(text, style='body'):
    return Paragraph(inline(text), STYLES[style])

def table_block(lines):
    rows = []
    for line in lines:
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if all(re.fullmatch(r':?-+:?', c) for c in cells):
            continue
        rows.append(cells)
    cols = max(map(len, rows))
    if cols == 2:
        widths = [WIDTH * .34, WIDTH * .66]
    elif cols == 3:
        widths = [WIDTH * .25, WIDTH * .40, WIDTH * .35]
    else:
        widths = [WIDTH / cols] * cols
    data = [[para(c, 'headcell' if i == 0 else 'cell') for c in row] for i, row in enumerate(rows)]
    tab = Table(data, colWidths=widths, repeatRows=1, hAlign='LEFT')
    tab.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), TEAL),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor('#F0F5F8')]),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('LEFTPADDING', (0,0), (-1,-1), 7), ('RIGHTPADDING', (0,0), (-1,-1), 7),
        ('TOPPADDING', (0,0), (-1,-1), 5.5), ('BOTTOMPADDING', (0,0), (-1,-1), 5.5),
        ('LINEBELOW', (0,0), (-1,0), .5, TEAL),
        ('LINEBELOW', (0,1), (-1,-1), .3, colors.HexColor('#D9E3EA')),
    ]))
    return tab

def parse_body(lines):
    story = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line or line.startswith('<!--'):
            i += 1; continue
        if line.startswith('# '):
            i += 1; continue
        if line.startswith('## '):
            story.append(para(line[3:], 'h2')); i += 1; continue
        if line.startswith('```'):
            i += 1; code = []
            while i < len(lines) and not lines[i].startswith('```'):
                code.extend(textwrap.wrap(lines[i], width=96, replace_whitespace=False,
                                          drop_whitespace=False) or [''])
                i += 1
            story.append(Preformatted('\n'.join(code), STYLES['code']))
            i += 1; continue
        if line.startswith('|'):
            tablines = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                tablines.append(lines[i]); i += 1
            story.extend([table_block(tablines), Spacer(1, 8)])
            continue
        img = re.fullmatch(r'!\[([^\]]*)\]\(([^)]+)\)', line)
        if img:
            path = DOCS / img[2]
            if not path.is_file():
                raise FileNotFoundError(path)
            from PIL import Image as PILImage
            with PILImage.open(path) as im:
                w, h = im.size
            elements = [Spacer(1, 6), Image(str(path), width=WIDTH, height=WIDTH*h/w), Spacer(1, 7)]
            j = i + 1
            while j < len(lines) and not lines[j].strip(): j += 1
            if j < len(lines) and lines[j].startswith('Şekil '):
                elements.append(para(lines[j], 'small')); i = j
            story.append(KeepTogether(elements)); i += 1; continue
        if re.match(r'^\d+\. ', line) or line.startswith('- '):
            story.append(para(line)); i += 1; continue
        parts = [line]; i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r'^(#|\||```|!\[|\d+\. |\- )', lines[i]):
            parts.append(lines[i].strip()); i += 1
        story.append(para(' '.join(parts)))
    return story

def page(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(TEAL); canvas.rect(0, 831, 596, 11, fill=1, stroke=0)
    canvas.setFont('UIBold', 8); canvas.setFillColor(INK)
    canvas.drawString(18*mm, 813, 'REMOTE OPS  /  ' + doc.short_title)
    canvas.setStrokeColor(colors.HexColor('#D8E2E9'))
    canvas.line(18*mm, 16*mm, 192*mm, 16*mm)
    canvas.setFont('UI', 7.5); canvas.setFillColor(colors.HexColor('#556B7B'))
    canvas.drawString(18*mm, 11*mm, 'v21 · 15 Ekim 2026 · Anlaşılır teşhis ve geri alma')
    canvas.drawRightString(192*mm, 11*mm, str(doc.page))
    canvas.restoreState()

def build(source, output, title):
    lines = (DOCS/source).read_text(encoding='utf-8-sig').splitlines()
    doc = SimpleDocTemplate(str(output), pagesize=(210*mm,297*mm),
                            leftMargin=18*mm, rightMargin=18*mm,
                            topMargin=19*mm, bottomMargin=19*mm,
                            title='RemoteOps — '+title, author='YD RemoteOps',
                            subject='YD_RemoteOps.App_v27 teknik ve operatör belgeleri')
    doc.short_title = title
    story = [Spacer(1, 28), para('YD REMOTEOPS APP', 'small'),
             para(title, 'title'), para('15 Ekim 2026 · YD_RemoteOps.App_v27', 'small'),
             para('Güncel kaynak yapısına göre hazırlanmıştır. Şirket kabul testleri operatör tarafından tamamlanacaktır. Ekran görüntüleri örnek veriler içerir.'),
             Spacer(1, 16), para('Bu belgede', 'h2')]
    for line in lines:
        if line.startswith('## '): story.append(para(line[3:], 'small'))
    story.append(PageBreak())
    # Date line is on the cover, omit its duplicate in the body.
    body = [l for l in lines if not l.startswith('15 Ekim 2026 ·')]
    story.extend(parse_body(body))
    doc.build(story, onFirstPage=page, onLaterPages=page)

def render(output):
    import pypdfium2 as pdfium
    from PIL import Image as PILImage, ImageDraw
    qa = Path(os.environ.get('TEMP', str(ROOT/'tmp'/'pdfs')))/'RemoteOps-Documentation-QA'/output.stem
    qa.mkdir(parents=True, exist_ok=True)
    pdf = pdfium.PdfDocument(str(output))
    thumbs=[]
    for n in range(len(pdf)):
        p=pdf[n]; bitmap=p.render(scale=1.25); im=bitmap.to_pil()
        im.save(qa/f'page-{n+1:02d}.png')
        thumb=im.copy(); thumb.thumbnail((238,340))
        tile=PILImage.new('RGB',(258,370),'#dfe7ec'); tile.paste(thumb,((258-thumb.width)//2,8))
        ImageDraw.Draw(tile).text((12,350),f'{output.stem} / {n+1}',fill='black')
        thumbs.append(tile); bitmap.close(); p.close()
    for offset in range(0,len(thumbs),12):
        batch=thumbs[offset:offset+12]; rows=(len(batch)+3)//4
        sheet=PILImage.new('RGB',(258*4,370*rows),'#dfe7ec')
        for n,t in enumerate(batch): sheet.paste(t,((n%4)*258,(n//4)*370))
        sheet.save(qa/f'contact-{offset//12+1:02d}.png')
    pdf.close()
    return len(thumbs)

if __name__ == '__main__':
    args=argparse.ArgumentParser(); args.add_argument('--render', action='store_true'); opts=args.parse_args()
    for source,output,title in DOCSETS:
        build(source,output,title)
        pages=render(output) if opts.render else '-'
        print(f'{output.name}: {pages} pages; {output.stat().st_size:,} bytes')
