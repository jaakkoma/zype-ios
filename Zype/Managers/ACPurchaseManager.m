//
//  ACPurchaseManager.m
//  Zype
//
//  Created by Александр on 21.04.17.
//  Copyright © 2017 Zype. All rights reserved.
//

#import "ACPurchaseManager.h"
#import <RMStore/RMStore.h>
#import <RMStore/RMAppReceipt.h>

@interface ACPurchaseManager()

@end

@implementation ACPurchaseManager

+ (id)sharedInstance {
    static ACPurchaseManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    if (self = [super init]) {
        self.subscriptions = [NSSet setWithObjects: kMonthlySubscription,
                              kYearlySubscription, nil];
    }
    return self;
}

- (BOOL)isActiveSubscription {
    RMAppReceipt *appReceipt = [RMAppReceipt bundleReceipt];
    if (appReceipt) {
        for (NSString *productID in self.subscriptions) {
            BOOL isActive =  [appReceipt containsActiveAutoRenewableSubscriptionOfProductIdentifier:productID forDate:[NSDate date]];
            if (isActive == true) {
                return true;
            }
        }

    }
    
    return false;
}

- (void)requestSubscriptions:(void(^)(NSArray *))success failure:(void(^)(NSString *))failure {
    [[RMStore defaultStore] requestProducts:self.subscriptions success:^(NSArray *products, NSArray *invalidProductIdentifiers) {
        if (products != nil) {
            success(products);
        } else {
            failure(@"Not products");
        }
    } failure:^(NSError *error) {
        failure(error.localizedDescription);
    }];
}

- (void)requestSubscriptions {
    [[RMStore defaultStore] requestProducts:self.subscriptions];
}

- (void)buySubscription:(NSString *)productID success:(void(^)())success failure:(void(^)(NSString *))failure {
    [[RMStore defaultStore] addPayment:productID success:^(SKPaymentTransaction *transaction) {
        
       if (success) {
           //verify with Bifrost
           [self verifyWithBifrost:^(){
               success();
           } failure:^(NSString *message){
               failure(message);
           }];
           
        }
       /* [[RMStore defaultStore].receiptVerificator verifyTransaction:transaction success:^{
        } failure:^(NSError *error) {
        }];*/
    } failure:^(SKPaymentTransaction *transaction, NSError *error) {
        if (failure) {
            failure(error.localizedDescription);
        }
    }];
}


- (void)verifyWithBifrost:(void(^)())success failure:(void(^)(NSString *))failure {
    // Load the receipt from the app bundle.
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
    if (!receipt) { /* No local receipt -- handle the error. */ }
    
    // Create the JSON object that describes the request
    NSError *error;
    NSDictionary *requestContents = @{
                                      @"consumer_id" : @"59244b8949ded9149b01a322",
                                      @"site_id" : @"123",
                                      @"subscription_plan_id" : @"5931ae930eda4a149d007c75",
                                      @"device_type" : @"ios",
                                      @"receipt": [receipt base64EncodedStringWithOptions:0],
                                      @"shared_key" : @"ead5fc19c42045cfa783e24d6e5a2325",
                                      @"app_key" : @"app key here"
                                      };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents
                                                          options:NSJSONWritingPrettyPrinted
                                                            error:&error];
    
    if (!requestData) { /* ... Handle error ... */ }
    
    // Create a POST request with the receipt data.
    NSURL *storeURL = [NSURL URLWithString:@"https://bifrost.stg.zype.com/api/v1/subscribe"];
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
    [storeRequest setValue:@"application/json" forHTTPHeaderField:@"Content-type"];
    [storeRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];
    

    
    //Response data object
    NSData *returnData = [[NSData alloc]init];
    
    //Send the Request
    returnData = [NSURLConnection sendSynchronousRequest: storeRequest returningResponse: nil error: nil];
    
    //Get the Result of Request
    NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:returnData options:NSJSONReadingAllowFragments error:&error];
    if(jsonResponse){
        int isValid = [[jsonResponse valueForKey:@"is_valid"] intValue];
        if (isValid == 1)
            success();
        
        int isExpired = [[jsonResponse valueForKey:@"is_expired"] intValue];
        if (isExpired == 1)
            failure(@"Your subscription has expired");
    } else {
        failure(error.localizedDescription);
    }
    failure(@"Can't subscribe at the moment. Try to subscribe on the website");
}


- (void)restorePurchases:(void(^)())success failure:(void(^)(NSString *))failure {
    [[RMStore defaultStore] restoreTransactionsOnSuccess:^(NSArray *transactions) {
        success();
    } failure:^(NSError *error) {
        failure(error.localizedDescription);
    }];
}

@end
