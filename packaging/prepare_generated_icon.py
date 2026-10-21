"""Format the selected generated raster asset as PNG and multi-size Windows ICO."""
from pathlib import Path
import argparse
import shutil
from PIL import Image

parser=argparse.ArgumentParser()
parser.add_argument('image',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
assets=root/'assets'
shutil.copy2(args.image,assets/'launcher-generated.png')
with Image.open(args.image) as image:
    image=image.convert('RGBA')
    image.resize((256,256),Image.Resampling.LANCZOS).save(assets/'launcher.png')
    image.save(assets/'launcher.ico',format='ICO',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)],bitmap_format='bmp')
print('Generated icon copied into project and converted to PNG/ICO.')
