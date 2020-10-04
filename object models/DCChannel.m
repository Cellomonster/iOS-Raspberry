//
//  DCChannel.m
//  Disco
//
//  Created by Trevir on 3/1/19.
//  Copyright (c) 2019 Trevir. All rights reserved.
//

#import "DCChannel.h"
#import "DCGuild.h"
#import "RBClient.h"
#import "DCGuildMember.h"
#import "DCUser.h"
#import "DCMessage.h"
#import "DCMessageAttatchment.h"
#import "DCPermissionOverwrite.h"
#import "RBNotificationEvent.h"

@interface DCChannel()

@property NSOperationQueue* imageLoadQueue;

@end

@implementation DCChannel
@synthesize snowflake = _snowflake;

- (DCChannel *)initFromDictionary:(NSDictionary *)dict andGuild:(DCGuild*)guild {
	self = [super init];
    
    if(![dict objectForKey:@"type"]){
		[NSException exceptionWithName:@"invalid dictionary"
                                reason:@"tried to initialize channel from invalid dictionary!"
                              userInfo:dict];
	}
    
    self.parentGuild = guild;
	
	self.snowflake = [dict objectForKey:@"id"];
	self.name = [dict objectForKey:@"name"];
    self.channelType = [[dict objectForKey:@"type"] intValue];
    self.lastMessageReadOnLoginSnowflake = [dict objectForKey:@"last_message_id"];
    
    if(!self.name || [self.name isKindOfClass:[NSNull class]]){
        //If no name, create a name from channel members
        NSMutableString* fullChannelName;
        
        if(self.channelType == DCChannelTypeDirectMessage){
            fullChannelName = [@"@" mutableCopy];
        }else{
            fullChannelName = [@"Group: @" mutableCopy];
        }
        
        NSArray* privateChannelMembers = [dict valueForKey:@"recipients"];
        for(NSDictionary* privateChannelMember in privateChannelMembers){
            //add comma between member names
            if([privateChannelMembers indexOfObject:privateChannelMember] != 0)
                [fullChannelName appendString:@", @"];
            
            NSString* memberName = [privateChannelMember valueForKey:@"username"];
            [fullChannelName appendString:memberName];
            
            self.name = fullChannelName;
        }
    }
    
    id sortingPositionId = [dict objectForKey:@"position"];
    if(sortingPositionId != nil){
        self.sortingPosition = [sortingPositionId intValue];
    }
    
    if(self.channelType == DCChannelTypeDirectMessage)return self;
    
    self.parentCatagorySnowflake = [dict objectForKey:@"parent_id"];
    if(self.parentCatagorySnowflake == nil){
        self.parentCatagorySnowflake = @"no cat";
    }
    
    NSArray* jsonPermissionOverwrites = (NSArray*)[dict objectForKey:@"permission_overwrites"];
    self.permissionOverwrites = [[NSMutableDictionary alloc] initWithCapacity:jsonPermissionOverwrites.count];
    for(NSDictionary* jsonPermissionOverwrite in jsonPermissionOverwrites){
        DCPermissionOverwrite* permOverwrite = [[DCPermissionOverwrite alloc] initWithDictionary:jsonPermissionOverwrite];
        if(permOverwrite.appliesToSnowflake != nil)
            [self.permissionOverwrites setObject:permOverwrite forKey:permOverwrite.appliesToSnowflake];
    }
    
    int isVisibleCode = 0;
    
    for(DCPermissionOverwrite* permOverwrite in [self.permissionOverwrites allValues]){
        
        if(permOverwrite.type == DCPermissionOverwriteTypeRole){
            
            //Check if this channel dictates permissions over any roles the user has
            if([guild.userGuildMember.roles objectForKey:permOverwrite.appliesToSnowflake]){
                
                if((permOverwrite.deny & 1024) == 1024 && isVisibleCode < 1)
                    isVisibleCode = 1;
                
                if(((permOverwrite.allow & 1024) == 1024) && isVisibleCode < 2)
                    isVisibleCode = 2;
            }
        }else{
            //Check if
            if([permOverwrite.appliesToSnowflake isEqualToString:guild.userGuildMember.user.snowflake]){
                
                if((permOverwrite.deny & 1024) == 1024 && isVisibleCode < 3)
                    isVisibleCode = 3;
                
                if((permOverwrite.allow & 1024) == 1024){
                    isVisibleCode = 4;
                    break;
                }
            }
        }
    }
    
    self.isVisible = (isVisibleCode == 0 || isVisibleCode == 2 || isVisibleCode == 4);
	
	return self;
}

- (NSMutableURLRequest*)authedMutableURLRequestFromString:(NSString*)requestString{
    
    NSString* baseString = @"https://discordapp.com/api/channels/%@%@";
    NSString* compositeString = [NSString stringWithFormat:baseString, self.snowflake, requestString];
    NSURL* url = [NSURL URLWithString:compositeString];
    
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:2];
    
    [urlRequest addValue:RBClient.sharedInstance.tokenString forHTTPHeaderField:@"Authorization"];
    [urlRequest addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    return urlRequest;
}

- (void)retrieveNumberOfMessages:(int)numMessages {
    self.messages = [NSMutableArray arrayWithCapacity:numMessages];
    
    NSString* requestString = [NSString stringWithFormat:@"/messages?limit=%i", numMessages];
	
	NSMutableURLRequest* request = [self authedMutableURLRequestFromString:requestString];
	
	NSError *error;
	NSHTTPURLResponse *responseCode;
	NSData *response = [NSURLConnection sendSynchronousRequest:request returningResponse:&responseCode error:&error];
    
    if(error){
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:error.localizedFailureReason message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
        return;
    }
	
	if(response){
		NSArray* parsedResponse = [NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
        
        for(id jsonMessage in parsedResponse){
            if([jsonMessage isKindOfClass:[NSDictionary class]]){
                DCMessage *message = [[DCMessage alloc] initFromDictionary:jsonMessage];
                [self addMessage:message];
            }
        }
	}
	
	self.messages = (NSMutableArray*)[[self.messages reverseObjectEnumerator] allObjects];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:RBNotificationEventFocusedChannelUpdated object:nil];
}

- (void)releaseMessages{
    self.messages = nil;
}

- (void)sendMessage:(NSString*)message {
    NSMutableURLRequest* request = [self authedMutableURLRequestFromString:@"/messages"];
    
    // janky way to escape the message string
    NSString* escapedMessage=[[NSString alloc] initWithData:
       [NSJSONSerialization dataWithJSONObject:@[message] options:0 error:nil]
                            encoding:NSUTF8StringEncoding];
    escapedMessage=[[escapedMessage substringToIndex:([escapedMessage length]-1)] substringFromIndex:1];
    
    NSString* messageString = [NSString stringWithFormat:@"{\"content\":%@}", escapedMessage];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[NSData dataWithBytes:[messageString UTF8String] length:[messageString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]];
    
    
    NSError *error = nil;
    NSHTTPURLResponse *responseCode = nil;
    
    [NSURLConnection sendSynchronousRequest:request returningResponse:&responseCode error:&error];
    
    if(error){
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:error.localizedFailureReason message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    }
}

- (void)markAsReadWithMessage:(DCMessage*)message{
    self.isRead = true;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSString* requestString = [NSString stringWithFormat:@"/messages/%@/ack", message.snowflake];
        
        NSMutableURLRequest* request = [self authedMutableURLRequestFromString:requestString];
        
        [request setHTTPMethod:@"POST"];
        
        NSString* fakeAckTokenData = @"{\"token\":\"a\"}";
        [request setHTTPBody:[NSData dataWithBytes:[fakeAckTokenData UTF8String] length:[fakeAckTokenData length]]];
        
        NSError *error = nil;
        NSHTTPURLResponse *responseCode = nil;
        
        [NSURLConnection sendSynchronousRequest:request returningResponse:&responseCode error:&error];
        
        if(error){
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:error.localizedFailureReason message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alertView show];
        }
        
    });
}

- (void)addMessage:(DCMessage*)message{
    [self.messages addObject:message];
    
    for(DCMessageAttatchment *messageAttachment in [message.attachments allValues]){
        [self.messages addObject:messageAttachment];
    }
    
    [message.author queueLoadAvatarImage];
    [message queueLoadAttachments];
}

- (void)handleNewMessage:(DCMessage*)message{
    if(self.isCurrentlyFocused){
        [self addMessage:message];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:RBNotificationEventFocusedChannelUpdated object:nil];
    }else{
        self.isRead = false;
    }
}

@end
