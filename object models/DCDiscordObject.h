//
//  DCDiscordObject.h
//  Disco
//
//  Created by Trevir on 3/2/19.
//  Copyright (c) 2019 Trevir. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DCDiscordObject : NSObject

@property NSString *snowflake;

-(id)initFromDictionary:(NSDictionary*)dict;

@end
