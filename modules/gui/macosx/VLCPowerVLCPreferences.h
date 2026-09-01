/*****************************************************************************
 * VLCPowerVLCPreferences.h: lightweight media-library preference panes
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

typedef struct intf_thread_t intf_thread_t;

@interface VLCPowerVLCPreferences : NSObject <NSTableViewDataSource,
    NSTableViewDelegate>

@property (readonly, strong) NSView *mediaLibraryView;
@property (readonly, strong) NSView *portablePlayersView;

- (instancetype)initWithInterface:(intf_thread_t *)intf;
- (void)reload;
- (void)save;

@end
