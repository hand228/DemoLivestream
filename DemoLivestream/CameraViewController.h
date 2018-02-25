//
//  CameraViewController.h
//  DemoLivestream
//
//  Created by Hà Nguyễn Đức on 2/25/18.
//  Copyright © 2018 DucHa. All rights reserved.
//

#import <UIKit/UIKit.h>
@protocol CameraViewControllerDelegate
- (void)didReceiveLandmarks:(NSArray *)landmarks;
@end
@interface CameraViewController : UIViewController
@property (weak, nonatomic) id<CameraViewControllerDelegate> delegate;
- (void)start;
- (void)stop;
@end
