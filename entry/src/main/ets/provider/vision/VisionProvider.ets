export interface VisionProvider {
  readonly providerName: string;
  available(): boolean;
  recognizeImageUri(imageUri: string): Promise<string>;
}
