from pathlib import Path
import re, html
from reportlab.platypus import SimpleDocTemplate,Paragraph,Spacer,Image,Preformatted,KeepTogether
from reportlab.lib.styles import getSampleStyleSheet,ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from PIL import Image as PILImage
root=Path(__file__).resolve().parents[1]
for name,font in [('Segoe','segoeui.ttf'),('SegoeBold','segoeuib.ttf'),('Mono','consola.ttf')]:
 pdfmetrics.registerFont(TTFont(name,str(Path('C:/Windows/Fonts')/font)))
styles=getSampleStyleSheet()
for k in ['Normal','BodyText','Heading1','Heading2','Heading3','Title']:
 styles[k].fontName='SegoeBold' if k.startswith('Heading') or k=='Title' else 'Segoe'
 styles[k].leading=15;styles[k].fontSize=10
styles['Title'].fontSize=22;styles['Title'].leading=27
styles['Heading1'].fontSize=17;styles['Heading1'].leading=22
styles['Heading2'].fontSize=14;styles['Heading2'].leading=19
styles['Heading3'].fontSize=12;styles['Heading3'].leading=16
styles.add(ParagraphStyle('CodeBlock',fontName='Mono',fontSize=7.5,leading=10,spaceAfter=8))
styles.add(ParagraphStyle('SmallTable',fontName='Segoe',fontSize=8.5,leading=12,spaceAfter=3))
def text(s):
 s=html.escape(s)
 s=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1',s)
 s=re.sub(r'\*\*(.*?)\*\*',r'<b>\1</b>',s)
 return s.replace('`','')
def footer(c,d):
 c.setFont('Segoe',8);c.setFillColor(colors.HexColor('#62778A'));c.drawString(42,24,'YD RemoteOps v28 · 16 Ekim 2026 · Önceki bölümler tarihli referanstır')
 c.drawRightString(553,24,str(d.page))
def build(src,dest):
 story=[];code=False;buf=[]
 for line in src.read_text(encoding='utf-8-sig').splitlines():
  if line.startswith('```'):
   if code:
    for part in buf:
     # Wrap code for a printable text reference; production code is in source files.
     for i in range(0,max(1,len(part)),95):story.append(Paragraph(html.escape(part[i:i+95]).replace(' ','&#160;'),'CodeBlock' if False else styles['CodeBlock']))
    buf=[]
   code=not code;continue
  if code:buf.append(line);continue
  if not line.strip():story.append(Spacer(1,5));continue
  im=re.match(r'!\[([^]]*)\]\(([^)]+)\)',line)
  if im:
   path=(src.parent/im[2]).resolve()
   if path.exists():
    w,h=PILImage.open(path).size;scale=min(510/w,600/h);story.append(Image(str(path),width=w*scale,height=h*scale));story.append(Paragraph(text(im[1]),styles['SmallTable']))
   continue
  h=re.match(r'^(#{1,4})\s+(.*)',line)
  if h:
   level=len(h[1]);story.append(Paragraph(text(h[2]),styles['Title' if level==1 else 'Heading'+str(min(3,level-1))]));continue
  if re.match(r'^\|?[\s:|-]+\|?$',line) and '-' in line:continue
  if line.startswith('|'):story.append(Paragraph(text(line.strip('|').replace('|',' · ')),styles['SmallTable']));continue
  if line.startswith('- '):line='• '+line[2:]
  story.append(Paragraph(text(line),styles['BodyText']))
 SimpleDocTemplate(str(dest),pagesize=(595,842),leftMargin=42,rightMargin=42,topMargin=38,bottomMargin=40,title='YD RemoteOps v28 — '+src.stem,author='YD RemoteOps').build(story,onFirstPage=footer,onLaterPages=footer)
 print(dest.name)
for src,dest in [('KULLANIM_KILAVUZU.md',root/'KULLANIM_KILAVUZU.pdf'),('TEKNIK_EL_KITABI.md',root/'docs/RemoteOps_Teknik_El_Kitabi.pdf'),('CALISMA_MANTIGI.md',root/'docs/RemoteOps_Calisma_Mantigi.pdf'),('INCELEME_RAPORU.md',root/'docs/RemoteOps_Inceleme_Raporu.pdf'),('GELECEK_OPERASYON_OLUSTUR.md',root/'docs/RemoteOps_Operasyon_Olustur_Tasarim.pdf')]:build(root/'docs'/src,dest)
