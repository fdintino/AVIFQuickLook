//
//  AVIFDecoder.m
//  AVIFQuickLook
//
//  Created by lizhuoli on 2019/4/15.
//  Copyright © 2019 dreampiggy. All rights reserved.
//

#import "AVIFDecoder.h"
#import <Accelerate/Accelerate.h>
#import <avif/avif.h>
#import <AppKit/AppKit.h>

// Convert 8/10/12bit AVIF image into RGBA8888
static BOOL ConvertAvifImagePlanarToRGB(avifDecoder *decoder, uint8_t * outPixels) {
    avifRGBImage rgb;
    avifResult result;

    memset(&rgb, 0, sizeof(rgb));
    avifRGBImageSetDefaults(&rgb, decoder->image);

    rgb.depth = 8;

    if (decoder->alphaPresent) {
        rgb.format = AVIF_RGB_FORMAT_RGBA;
    } else {
        rgb.format = AVIF_RGB_FORMAT_RGB;
        rgb.ignoreAlpha = AVIF_TRUE;
    }

    avifRGBImageAllocatePixels(&rgb);

    result = avifImageYUVToRGB(decoder->image, &rgb);

    if (result != AVIF_RESULT_OK) {
        avifRGBImageFreePixels(&rgb);
        return FALSE;
    }

    memcpy(outPixels, rgb.pixels, rgb.rowBytes * rgb.height);
    avifRGBImageFreePixels(&rgb);
    return TRUE;
}

static void FreeImageData(void *info, const void *data, size_t size) {
    free((void *)data);
}

@implementation AVIFDecoder

+ (nullable CGImageRef)createAVIFImageAtPath:(nonnull NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    if (![AVIFDecoder isAVIFFormatForData:data]) {
        return nil;
    }
    
    return [AVIFDecoder createAVIFImageWithData:data];
}

+ (nullable CGImageRef)createAVIFImageWithData:(nonnull NSData *)data CF_RETURNS_RETAINED {
    // Decode it
    avifDecoder *decoder = avifDecoderCreate();
    avifResult result;
    avifDecoderSetIOMemory(decoder, (uint8_t *)data.bytes, data.length);

    result = avifDecoderParse(decoder);

    if (result != AVIF_RESULT_OK) {
        avifDecoderDestroy(decoder);
        return nil;
    }

    result = avifDecoderNextImage(decoder);
    if (result != AVIF_RESULT_OK) {
        avifDecoderDestroy(decoder);
        return nil;
    }
    
    int width = decoder->image->width;
    int height = decoder->image->height;
    BOOL hasAlpha = decoder->image->alphaPlane != NULL;
    size_t components = hasAlpha ? 4 : 3;
    size_t bitsPerComponent = 8;
    size_t bitsPerPixel = components * bitsPerComponent;
    size_t rowBytes = width * bitsPerPixel / 8;
    
    uint8_t * dest = calloc(width * components * height, sizeof(uint8_t));
    if (!dest) {
        avifDecoderDestroy(decoder);
        return nil;
    }
    // convert planar to RGB888/RGBA8888
    if (!ConvertAvifImagePlanarToRGB(decoder, dest)) {
        avifDecoderDestroy(decoder);
        return nil;
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, dest, rowBytes * height, FreeImageData);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    bitmapInfo |= hasAlpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNone;
    CGColorSpaceRef colorSpaceRef = [self colorSpaceGetDeviceRGB];
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    CGImageRef imageRef = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, rowBytes, colorSpaceRef, bitmapInfo, provider, NULL, NO, renderingIntent);
    
    // clean up
    CGDataProviderRelease(provider);
    avifDecoderDestroy(decoder);
    
    return imageRef;
}

#pragma mark - Helper
+ (BOOL)isAVIFFormatForData:(nullable NSData *)data
{
    if (!data) {
        return NO;
    }
    if (data.length >= 12) {
        //....ftypavif ....ftypavis
        NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(4, 8)] encoding:NSASCIIStringEncoding];
        if ([testString isEqualToString:@"ftypavif"]
            || [testString isEqualToString:@"ftypavis"]) {
            return YES;
        }
    }
    
    return NO;
}

+ (CGColorSpaceRef)colorSpaceGetDeviceRGB {
    CGColorSpaceRef screenColorSpace = NSScreen.mainScreen.colorSpace.CGColorSpace;
    if (screenColorSpace) {
        return screenColorSpace;
    }
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateDeviceRGB();
    });
    return colorSpace;
}

@end
