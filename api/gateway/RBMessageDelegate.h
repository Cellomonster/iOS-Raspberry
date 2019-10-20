//
//  RBMessageDelegate.h
//  raspberry
//
//  Created by trevir on 10/19/19.
//  Copyright (c) 2019 Trevir. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol RBMessageDelegate <NSObject>

-(void)handleMessageCreate:(NSDictionary *)dict;

@end