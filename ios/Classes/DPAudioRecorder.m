    //
    //  AmrRecorder.m
    //  aaaa
    //
    //  Created by Andrew on 2017/7/17.
    //  Copyright © 2017年 Andrew. All rights reserved.
    //

#import "DPAudioRecorder.h"
#import "DPAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "JX_GCDTimerManager.h"
#import "amr_wav_converter.h" 

#define MAX_RECORDER_TIME 210
#define MIN_RECORDER_TIME 1

#define TimerName @"audioTimer_999"
typedef NS_ENUM(NSUInteger, CSVoiceType) {
    CSVoiceTypeWav,
    CSVoiceTypeAmr
};

static const CSVoiceType preferredVoiceType = CSVoiceTypeWav;
@interface DPAudioRecorder () <AVAudioRecorderDelegate>
{
    BOOL isRecording;
    dispatch_source_t timer;
    NSTimeInterval __block audioTimeLength; //录音时长
}

@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong, readonly) NSString *originWaveFilePath;
@property (nonatomic, strong, readonly) NSString *amrFilePath;
@property (nonatomic, strong, readonly) NSString *convertedWaveFilePath;
@property (nonatomic, strong) NSDate *_date;


@end

@implementation DPAudioRecorder

- (NSString *)originWaveFilePath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"WAVtemporaryRadio_%@.wav",[NSString stringWithFormat:@"%.0f", [self._date timeIntervalSince1970]*1000]
                                                                   ]
            ];
}

- (NSString *)amrFilePath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"AMRtemporaryRadio_%@.amr",[NSString stringWithFormat:@"%.0f", [self._date timeIntervalSince1970]*1000]
                                                                   ]
            ];
}

- (NSString *)convertedWaveFilePath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"WAVtemporaryRadio2_%@.wav",[NSString stringWithFormat:@"%.0f", [self._date timeIntervalSince1970]*1000]
                                                                   ]
            ];
}

static DPAudioRecorder *recorderManager = nil;
+ (DPAudioRecorder *)sharedInstance
{
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken,^{
        recorderManager = [[DPAudioRecorder alloc] init];
        recorderManager._date=[NSDate date];
    });
    
    return recorderManager;
}

- (instancetype)init
{
    if (self = [super init]) {
            //创建缓存录音文件到Tmp
        NSString *wavRecordFilePath = self.originWaveFilePath;
        if (![[NSFileManager defaultManager] fileExistsAtPath:wavRecordFilePath]) {
            [[NSData data] writeToFile:wavRecordFilePath atomically:YES];
        }
        
        NSString *amrRecordFilePath = self.amrFilePath;
        if (![[NSFileManager defaultManager] fileExistsAtPath:amrRecordFilePath]) {
            [[NSData data] writeToFile:amrRecordFilePath atomically:YES];
        }
        
        NSString *convertedWaveFilePath = self.convertedWaveFilePath;
        if (![[NSFileManager defaultManager] fileExistsAtPath:convertedWaveFilePath]) {
            [[NSData data] writeToFile:convertedWaveFilePath atomically:YES];
        }
        NSLog(@"录制文件路径 %@",wavRecordFilePath);
        
    }
    return self;
}

- (void)startRecording
{
    if (isRecording) return;
    
    [[DPAudioPlayer sharedInstance]stopPlaying];
        //开始录音
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error:nil];
        //    //默认情况下扬声器播放
    AVAudioSessionPortOverride portOverride = AVAudioSessionPortOverrideNone;
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:portOverride error:nil];
    
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    
    [self.audioRecorder prepareToRecord];
    
    [self.audioRecorder record];
    
    if ([self.audioRecorder isRecording]) {
        isRecording = YES;
        [self activeTimer];
        if (self.audioStartRecording) {
            self.audioStartRecording(YES);
        }
    } else {
        if (self.audioStartRecording) {
            self.audioStartRecording(NO);
        }
    }
    
    
    [self createPickSpeakPowerTimer];
}

- (void)stopRecording;
{
    if (!isRecording) return;
        //  try!AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
    [self shutDownTimer];
    [self.audioRecorder stop];
    self.audioRecorder = nil;
    
        //设置播放语音为k公开模式
    AVAudioSession *avAudioSession = [AVAudioSession sharedInstance];
    [avAudioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    
}

- (void)activeTimer
{
    
        //录音时长
    audioTimeLength = 0;
    NSTimeInterval timeInterval = 0.1;
    __weak typeof(self) weakSelf = self;
    [[JX_GCDTimerManager sharedInstance] scheduledDispatchTimerWithName:TimerName timeInterval:timeInterval queue:nil repeats:YES actionOption:AbandonPreviousAction action:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf->audioTimeLength += timeInterval;
        if (strongSelf->audioTimeLength >= MAX_RECORDER_TIME) { //大于等于 MAX_RECORDER_TIME 秒停止
            [strongSelf stopRecording];
        }
    }];
}

- (void)shutDownTimer
{
    [[JX_GCDTimerManager sharedInstance] cancelAllTimer];//定时器停止
}

- (AVAudioRecorder *)audioRecorder {
    if (!_audioRecorder) {
        
            //暂存录音文件路径
        NSString *wavRecordFilePath = self.originWaveFilePath;
        NSLog(@"%@", wavRecordFilePath);
        NSDictionary *param =
        @{AVSampleRateKey:@8000.0,    //采样率
          AVFormatIDKey:@(kAudioFormatLinearPCM),//音频格式
          AVLinearPCMBitDepthKey:@16,    //采样位数 默认 16
          AVNumberOfChannelsKey:@1,   // 通道的数目
          //          AVEncoderAudioQualityKey:@(AVAudioQualityHigh),
          //          AVEncoderBitRateKey:@128000,
          //          AVEncoderBitRateStrategyKey:AVAudioBitRateStrategy_VariableConstrained
        };
        
        NSError *initError;
        NSURL *fileURL = [NSURL fileURLWithPath:wavRecordFilePath];
        _audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:param error:&initError];
        if (initError) {
            NSLog(@"AVAudioRecorder initError:%@", initError.localizedDescription);
        }
        _audioRecorder.delegate = self;
        _audioRecorder.meteringEnabled = YES;
    }
    return _audioRecorder;
}

#pragma mark - AVAudioRecorder

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
        //暂存录音文件路径
    NSString *wavRecordFilePath = self.originWaveFilePath;
    NSLog(@"录音暂存位置 %@ ",wavRecordFilePath);
    NSData *cacheAudioData;
    switch (preferredVoiceType) {
        case CSVoiceTypeWav:
            cacheAudioData = [NSData dataWithContentsOfFile:wavRecordFilePath];
            break;
        case CSVoiceTypeAmr: {
            NSString *amrRecordFilePath = self.amrFilePath;
                //重点:把wav录音文件转换成amr文件,用于网络传输.amr文件大小是wav文件的十分之一左右
            wave_file_to_amr_file([wavRecordFilePath cStringUsingEncoding:NSUTF8StringEncoding],[amrRecordFilePath cStringUsingEncoding:NSUTF8StringEncoding], 1, 16);
                //返回amr音频文件Data,用于传输或存储
            cacheAudioData = [NSData dataWithContentsOfFile:amrRecordFilePath];
        } break;
    }
    
        //大于最小录音时长时,发送数据
    if (audioTimeLength > MIN_RECORDER_TIME) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSUInteger location = 4100;
            NSData *body = [cacheAudioData subdataWithRange:NSMakeRange(location, cacheAudioData.length - location)];
            NSMutableData *data1 = WriteWavFileHeader(body.length + 44, 8000, 1, 16).mutableCopy;
            [data1 appendData:body];
                //            NSLog(@"date1date1date1date1[0-200]:%@", [data1 subdataWithRange:NSMakeRange(0, 200)]);
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.audioRecorderFinishRecording) {
                    self.audioRecorderFinishRecording(data1, self->audioTimeLength,wavRecordFilePath);
                }
            });
        });
    } else {
        if (self.audioRecordingFail) {
            self.audioRecordingFail(@"录音时长小于设定最短时长");
        }
    }
    
    isRecording = NO;
    
        //取消定时器
    if (timer) {
        dispatch_source_cancel(timer);
        timer = NULL;
    }
}

NSData* WriteWavFileHeader(long lengthWithHeader, int sampleRate, int channels, int PCMBitDepth) {
    Byte header[44];
    header[0] = 'R';  // RIFF/WAVE header
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    long totalDataLen = lengthWithHeader - 8;
    header[4] = (Byte) (totalDataLen & 0xff);  //file-size (equals file-size - 8)
    header[5] = (Byte) ((totalDataLen >> 8) & 0xff);
    header[6] = (Byte) ((totalDataLen >> 16) & 0xff);
    header[7] = (Byte) ((totalDataLen >> 24) & 0xff);
    header[8] = 'W';  // Mark it as type "WAVE"
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
    header[12] = 'f';  // Mark the format section 'fmt ' chunk
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
    header[16] = 16;   // 4 bytes: size of 'fmt ' chunk, Length of format data.  Always 16
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    header[20] = 1;  // format = 1 ,Wave type PCM
    header[21] = 0;
    header[22] = (Byte) channels;  // channels
    header[23] = 0;
    header[24] = (Byte) (sampleRate & 0xff);
    header[25] = (Byte) ((sampleRate >> 8) & 0xff);
    header[26] = (Byte) ((sampleRate >> 16) & 0xff);
    header[27] = (Byte) ((sampleRate >> 24) & 0xff);
    int byteRate = sampleRate * channels * PCMBitDepth >> 3;
    header[28] = (Byte) (byteRate & 0xff);
    header[29] = (Byte) ((byteRate >> 8) & 0xff);
    header[30] = (Byte) ((byteRate >> 16) & 0xff);
    header[31] = (Byte) ((byteRate >> 24) & 0xff);
    header[32] = (Byte) (channels * PCMBitDepth >> 3); // block align
    header[33] = 0;
    header[34] = PCMBitDepth; // bits per sample
    header[35] = 0;
    header[36] = 'd'; //"data" marker
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
    long totalAudioLen = lengthWithHeader - 44;
    header[40] = (Byte) (totalAudioLen & 0xff);  //data-size (equals file-size - 44).
    header[41] = (Byte) ((totalAudioLen >> 8) & 0xff);
    header[42] = (Byte) ((totalAudioLen >> 16) & 0xff);
    header[43] = (Byte) ((totalAudioLen >> 24) & 0xff);
    return [[NSData alloc] initWithBytes:header length:44];;
}

    //音频值测量
- (void)createPickSpeakPowerTimer
{
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
    
    __weak __typeof(self) weakSelf = self;
    
    dispatch_source_set_event_handler(timer, ^{
        __strong __typeof(weakSelf) _self = weakSelf;
        
        [_self->_audioRecorder updateMeters];
        double lowPassResults = pow(10, (0.05 * [_self->_audioRecorder peakPowerForChannel:0]));
        if (_self.audioSpeakPower) {
            _self.audioSpeakPower(lowPassResults);
        }
    });
    
    dispatch_resume(timer);
}

- (void)dealloc
{
    if (isRecording) [self.audioRecorder stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
