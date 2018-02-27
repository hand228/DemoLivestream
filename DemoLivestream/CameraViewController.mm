//
//  CameraViewController.m
//  DemoLivestream
//
//  Created by Hà Nguyễn Đức on 2/25/18.
//  Copyright © 2018 DucHa. All rights reserved.
//

#import "CameraViewController.h"
///// opencv
#import <opencv2/videoio/cap_ios.h>
#import <opencv2/opencv.hpp>
///// C++
#include <iostream>
///// user
#include "FaceARDetectIOS.h"

@interface CameraViewController () <CvVideoCameraDelegate>
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) CvVideoCamera* videoCamera;
@end

@implementation CameraViewController {
    FaceARDetectIOS *facear;
    int frame_count;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.videoCamera = [[CvVideoCamera alloc] initWithParentView:self.imageView];
    self.videoCamera.delegate = self;
    self.videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionFront;
    self.videoCamera.defaultAVCaptureSessionPreset = AVCaptureSessionPreset1280x720;
    self.videoCamera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
    self.videoCamera.defaultFPS = 20;
    self.videoCamera.grayscaleMode = NO;
    [[FaceARDetectIOS alloc] init];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)start {
    [self.videoCamera start];
}

- (void)stop {
    [self.videoCamera stop];
}

- (IBAction)actionStart:(UIButton *)sender {
    [self start];
}

- (void)processImage:(cv::Mat &)image
{
    cv::Mat targetImage(image.cols,image.rows,CV_8UC3);
    cv::cvtColor(image, targetImage, cv::COLOR_BGRA2BGR);
    if(targetImage.empty()){
        std::cout << "targetImage empty" << std::endl;
    }
    else
    {
        float fx, fy, cx, cy;
        cx = 1.0*targetImage.cols / 2.0;
        cy = 1.0*targetImage.rows / 2.0;
        
        fx = 500 * (targetImage.cols / 640.0);
        fy = 500 * (targetImage.rows / 480.0);
        
        fx = (fx + fy) / 2.0;
        fy = fx;
        
        //        [[FaceARDetectIOS alloc] run_FaceAR:targetImage frame__:frame_count fx__:fx fy__:fy cx__:cx cy__:cy];
        NSArray *landmarks = [[FaceARDetectIOS alloc] landmarks:targetImage frame__:frame_count fx__:fx fy__:fy cx__:cx cy__:cy];
        [self.delegate didReceiveLandmarks:landmarks];
        frame_count = frame_count + 1;
    }
    cv::cvtColor(targetImage, image, cv::COLOR_BGRA2RGB);
}
@end
