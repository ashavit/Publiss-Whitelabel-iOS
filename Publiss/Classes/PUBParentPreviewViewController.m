//
//  PUBParentPreviewViewController.m
//  Publiss
//
//  Copyright (c) 2014 Publiss GmbH. All rights reserved.
//

#import "PUBParentPreviewViewController.h"
#import "PUBDocumentFetcher.h"
#import "PUBDocument+Helper.h"
#import "PUBPreviewCell.h"
#import "UIColor+PUBDesign.h"
#import "PUBPagePreviewViewController.h"
#import "UIImageView+AFNetworking.h"
#import "PUBThumbnailImageCache.h"
#import "IAPController.h"
#import "PUBCommunication.h"
#import "JDStatusBarNotification.h"
#import "PUBURLFactory.h"
#import "PUBDocumentFetcher.h"
#import "PUBConstants.h"

@interface PUBParentPreviewViewController ()

@end



@implementation PUBParentPreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.downloadButton.color = [UIColor publissPrimaryColor];
    [self.downloadButton addTarget:self action:@selector(downloadButtonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [JDStatusBarNotification addStyleNamed:PurchasingMenuStyle
                                   prepare:^JDStatusBarStyle *(JDStatusBarStyle *style) {
                                       style.barColor = [UIColor publissPrimaryColor];
                                       style.textColor = [UIColor whiteColor];
                                       style.animationType = JDStatusBarAnimationTypeMove;
                                       style.font = [UIFont boldSystemFontOfSize:13.f];
                                       style.progressBarColor = [UIColor whiteColor];
                                       style.progressBarHeight = 20.0;
                                       return style;
                                   }];
    [self updateUI];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (PUBIsiPad() && !CGRectEqualToRect(self.oldViewFrame, CGRectZero)) {
        self.view.alpha = 0.f;
    }
    [self.downloadButton showActivityIndicator];
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // layout description text to top left corner
    [self.descriptionText sizeToFit];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (PUBIsiPad()) {
        if (!CGRectEqualToRect(self.oldViewFrame, CGRectZero)) {
            self.view.frame = self.oldViewFrame;
            [UIView animateWithDuration:0.3f
                             animations:^{ self.view.alpha = 1.0f; }];
        }
        
        self.recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        self.recognizer.numberOfTapsRequired = 1;
        self.recognizer.cancelsTouchesInView = NO;
        [self.view.window addGestureRecognizer:self.recognizer];
    }
    
    [PUBDocumentFetcher.sharedFetcher checkIfDocumentIsUnpublished:self.document competionHandler:^(BOOL unpublished) {
        if (unpublished) {
            [self dismissViewControllerAnimated:YES completion:^{
                if (self.kioskController) {
                    [self.kioskController refreshDocumentsWithActivityViewAnimated:YES];
                }
            }];
        } else {
            [self updateButtonUI];
        }
    }];
}

#pragma mark - Dismiss ViewController

// http://stackoverflow.com/questions/2623417/iphone-sdk-dismissing-modal-viewcontrollers-on-ipad-by-clicking-outside-of-it
// FOR iOS8 and iOS7.1: http://stackoverflow.com/a/25844208
- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        UIView *rootView = self.view.window.rootViewController.view;
        CGPoint location = [sender locationInView:rootView];
        if (![self.view pointInside:[self.view convertPoint:location fromView:rootView] withEvent:nil]) {
            [self dismissViewControllerAnimated:YES completion:^{
                [self.view.window removeGestureRecognizer:sender];
            }];
        }
    }
}

- (void)downloadButtonTouchUpInside:(id)sender {
    if ([sender isKindOfClass:PUBDownloadButton.class]) {
        if (!self.document.paid || [IAPController.sharedInstance hasPurchased:self.document.productID]) {
            [self openPDFWithWithDocument:self.document];
        }
        else {
            if (self.product != nil) {
                [self startPaymentProcess];
                
                [IAPController.sharedInstance purchase:self.document
                                            completion:^(SKPaymentTransaction *transaction) {
                                                
                                                [IAPController.sharedInstance readReceiptDataWithCompletion:^(NSData *receipt) {
                                                    [PUBCommunication.sharedInstance sendReceiptData:receipt
                                                                                       withProductID:self.document.productID
                                                                                         publishedID:@(self.document.publishedID)
                                                                                          completion:^(id responseObject) {
                                                                                              
                                                                                              BOOL shouldOpenDocument = NO;
                                                                                              if ([NSJSONSerialization isValidJSONObject:responseObject]) {
                                                                                                  NSDictionary *jsonData = (NSDictionary *)responseObject;
                                                                                                  NSString *secret = PUBSafeCast(jsonData[PUBJSONSecret], NSString.class);
                                                                                                  
                                                                                                  if (secret.length > 0) {
                                                                                                      shouldOpenDocument = YES;
                                                                                                      [IAPController.sharedInstance setIAPSecret:secret productID:self.document.productID];
                                                                                                      [NSNotificationCenter.defaultCenter postNotificationName:PUBDocumentPurchaseFinishedNotification
                                                                                                                                                        object:nil
                                                                                                                                                      userInfo:@{@"productID": self.document.productID}];
                                                                                                  }
                                                                                              }
                                                                                              
                                                                                              [self finishPaymentProcess];
                                                                                              if (shouldOpenDocument) {
                                                                                                  [self openPDFWithWithDocument:self.document];
                                                                                              }
                                                                                          } error:^(NSError *error) {
                                                                                              [self finishPaymentProcess];
                                                                                          }];
                                                } error:^(NSError *error) {
                                                    PUBLogError(@"%@: Error reading receipt: %@", self.class, error.localizedDescription);
                                                    [self finishPaymentProcess];
                                                }];
                                            }
                                                 error:^(NSError *error) {
                                                     PUBLogError(@"Error purchasing document: %@", error);
                                                     [self finishPaymentProcess];
                                                     
                                                     if (error.code != SKErrorPaymentCancelled) {
                                                         [[[UIAlertView alloc] initWithTitle:PUBLocalize(@"Error")
                                                                                     message:PUBLocalize(@"The document could not be purchased. Please try again later.")
                                                                                    delegate:nil
                                                                           cancelButtonTitle:PUBLocalize(@"OK")
                                                                           otherButtonTitles:nil] show];
                                                     }
                                                 }];
            }
        }
    }
}

- (void)startPaymentProcess {
    __block PUBDownloadButton *downloadButton = self.downloadButton;
    [JDStatusBarNotification showWithStatus:PUBLocalize(@"Processing Purchase...") styleName:PurchasingMenuStyle];
    [JDStatusBarNotification showActivityIndicator:YES indicatorStyle:UIActivityIndicatorViewStyleWhite];
    [downloadButton showActivityIndicator];
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
}

- (void)finishPaymentProcess {
    __block PUBDownloadButton *downloadButton = self.downloadButton;
    
    if ([[UIApplication sharedApplication] isIgnoringInteractionEvents]) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    }
    
    [downloadButton setupDownloadButtonWithPUBDocument:self.document];
    [downloadButton hideActivityIndicator];
    [JDStatusBarNotification dismiss];
}

- (void)openPDFWithWithDocument:(PUBDocument *)document {
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.kioskController) {
            [self.kioskController presentDocument:document];
        }
    }];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    // maximum 5 preview pages
    return MIN(5, self.document.pageCount + 1);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"PreviewCell";
    PUBPreviewCell *cell =
    (PUBPreviewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    cell.previewImageView.image = nil;
    
    NSString *previewImageURL = [PUBURLFactory createPreviewImageURLStringForDocument:self.document.publishedID page:indexPath.row];
    
    __weak PUBPreviewCell *weakCell = cell;
    NSURLRequest *urlrequest = [NSURLRequest requestWithURL:[NSURL URLWithString:previewImageURL]];
    
    if ([PUBThumbnailImageCache.sharedInstance thumbnailImageWithURLString:previewImageURL]) {
        cell.previewImageView.image = [PUBThumbnailImageCache.sharedInstance thumbnailImageWithURLString:previewImageURL];
    } else {
        [weakCell.activityIndicator startAnimating];
        [cell.previewImageView setImageWithURLRequest:urlrequest
                                 placeholderImage:nil
                                          success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
                                              PUBPreviewCell *strongCell = weakCell;
                                              strongCell.previewImageView.image = image;
                                              strongCell.previewImageView.alpha = 0.f;
                                              [strongCell.activityIndicator stopAnimating];
                                              [strongCell setNeedsLayout];
                                              [PUBThumbnailImageCache.sharedInstance setImage:image forURLString:previewImageURL];
                                              
                                              [UIView animateWithDuration:.25f animations:^{
                                                  strongCell.previewImageView.alpha = 1.f;
                                              } completion:NULL];
                                              
                                          } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
                                              PUBLogError(@"%@: Error fetching Previewimage URL, %@", [self class], error.localizedDescription);
                                          }];
    }
    return cell;
}

#pragma mark - UICollectionView Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (PUBIsiPad()) {
        self.oldViewFrame = self.view.frame;
    }
    
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"PUBKiosk" bundle:nil];
    PUBPagePreviewViewController *pagePreviewController = [storyboard instantiateViewControllerWithIdentifier:@"PagePreview"];
    pagePreviewController.document = self.document;
    pagePreviewController.initialPage = indexPath.row;
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:pagePreviewController];
    navController.navigationBar.tintColor = [UIColor publissPrimaryColor];
    [self presentViewController:navController animated:YES completion:NULL];
}

#pragma mark - Helper

- (void)updateUI {
    if (self.document.fileSize > 0) {
        static NSDateFormatter *dateFormatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dateFormatter = [NSDateFormatter new];
            [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        });
        NSString *shortDatestring = [NSString stringWithFormat:@"%@", [dateFormatter stringFromDate:self.document.updatedAt]];
        NSString *fileSize = [NSByteCountFormatter stringFromByteCount:self.document.fileSize countStyle:NSByteCountFormatterCountStyleFile];
        self.fileDescription.text = [NSString stringWithFormat:@"%@%@%@", fileSize, @" / ",shortDatestring];
    }
    [self defineDescriptionText];
}

- (void)updateButtonUI {
    if (self.document.paid) {
        [self.downloadButton showActivityIndicator];
        [IAPController.sharedInstance fetchProductForDocument:self.document
                                                   completion:^(SKProduct *product) {
                                                       if ([IAPController.sharedInstance canPurchase]) {
                                                           self.downloadButton.enabled = YES;
                                                           self.product = product;
                                                           
                                                           static NSNumberFormatter *numberFormatter = nil;
                                                           static dispatch_once_t onceToken;
                                                           dispatch_once(&onceToken, ^{
                                                               numberFormatter = [NSNumberFormatter new];
                                                               [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
                                                               numberFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
                                                               numberFormatter.locale = self.product.priceLocale;
                                                           });
                                                           [self.downloadButton setTitle:[numberFormatter stringFromNumber:self.product.price] forState:UIControlStateNormal];
                                                           [self.downloadButton setupDownloadButtonWithPUBDocument:self.document];
                                                           [self.downloadButton hideActivityIndicator];
                                                       }
                                                   }
                                                        error:^(NSError *error) {
                                                            [self.downloadButton setupDownloadButtonWithPUBDocument:self.document];
                                                            [self.downloadButton hideActivityIndicator];
                                                            
                                                            [[[UIAlertView alloc] initWithTitle:PUBLocalize(@"Error")
                                                                                        message:PUBLocalize(@"Could not retrieve product information. Please try again later.")
                                                                                       delegate:nil
                                                                              cancelButtonTitle:PUBLocalize(@"OK")
                                                                              otherButtonTitles:nil] show];
                                                            [self.downloadButton setNeedsDisplay];
                                                            
                                                        }];
    } else {
        [self.downloadButton hideActivityIndicator];
        [self.downloadButton setTitle:PUBLocalize(@"Free") forState:UIControlStateNormal];
    }
}


- (void)defineDescriptionText {
    self.titleLabel.text = self.document.title;
    self.descriptionTitle.text = PUBLocalize(@"Description");
    self.descriptionText.text = self.document.fileDescription.length > 0 ? self.document.fileDescription : @"";
    
    if (PUBIsiPad()) {
        UIFont *fontTtitle = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        
        UIFont *fontDescription = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        
        UIFont *fontDescriptionTitle = [UIFont boldSystemFontOfSize:12.0f];
        
        UIColor *textColorBlack = [UIColor blackColor];
        UIColor *textColorGray =  [UIColor lightGrayColor];
        
        NSDictionary *attrsDescription =
        @{ NSForegroundColorAttributeName : textColorBlack, NSFontAttributeName : fontDescription };
        NSDictionary *attrsTitle = @{ NSForegroundColorAttributeName : textColorBlack, NSFontAttributeName : fontTtitle };
        NSDictionary *attrsDescriptionTitle = @{NSForegroundColorAttributeName: textColorBlack, NSFontAttributeName : fontDescriptionTitle };
        NSDictionary *attrsFileDescription =
        @{ NSForegroundColorAttributeName : textColorGray, NSFontAttributeName : fontDescription };
        
        self.descriptionText.attributedText =  [[NSAttributedString alloc] initWithString:self.descriptionText.text attributes:attrsDescription];
        self.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:self.titleLabel.text attributes:attrsTitle];
        self.descriptionTitle.attributedText =  [[NSAttributedString alloc] initWithString:self.descriptionTitle.text attributes:attrsDescriptionTitle];
        self.fileDescription.attributedText =  [[NSAttributedString alloc] initWithString:self.fileDescription.text attributes:attrsFileDescription];
    } else {
        UIFont *fontTitle = [UIFont boldSystemFontOfSize:14.f];
        UIFont *fontDescription = [UIFont systemFontOfSize:11.f];
        UIColor *textColorBlack = [UIColor blackColor];
        UIColor *textColorGray =  [UIColor lightGrayColor];
        
        self.descriptionText.attributedText = [[NSAttributedString alloc] initWithString:self.descriptionText.text attributes:@{NSForegroundColorAttributeName : textColorBlack, NSFontAttributeName : fontDescription}];
        self.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:self.titleLabel.text attributes:@{NSForegroundColorAttributeName : textColorBlack, NSFontAttributeName : fontTitle}];
        self.fileDescription.attributedText = [[NSAttributedString alloc] initWithString:self.fileDescription.text attributes:@{NSForegroundColorAttributeName : textColorGray, NSFontAttributeName : fontDescription}];
    }

}

@end
