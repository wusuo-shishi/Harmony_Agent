import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VisionProvider } from './VisionProvider';

export class CoreVisionOcrProvider implements VisionProvider {
  readonly providerName: string = 'CoreVision OCR(真机)';

  available(): boolean {
    return true;
  }

  async recognizeImageUri(imageUri: string): Promise<string> {
    let fd: number = -1;
    try {
      fd = fs.openSync(imageUri, fs.OpenMode.READ_ONLY).fd;
      const source: image.ImageSource = image.createImageSource(fd);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const info: textRecognition.VisionInfo = { pixelMap: pixelMap };
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(info);
      return result.value;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`OCR 识别失败(code=${e.code}, message=${e.message})`);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (err) {
        }
      }
    }
  }
}
