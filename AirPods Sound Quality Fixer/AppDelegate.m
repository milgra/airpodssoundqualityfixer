#import "AppDelegate.h"
#import "GBLaunchAtLogin.h"
#import <CoreAudio/CoreAudio.h>


@interface AppDelegate ( )
{
    BOOL paused;
    NSMenu* menu;
    NSStatusItem* statusItem;
    AudioDeviceID forcedInputID;
    NSUserDefaults* defaults;
    NSMutableDictionary* itemsToIDS;
    NSMenuItem *startupItem;
}

@property (weak) IBOutlet NSWindow *window;

@end


@implementation AppDelegate


OSStatus callbackFunction(  AudioObjectID inObjectID,
                            UInt32 inNumberAddresses,
                            const AudioObjectPropertyAddress inAddresses[],
                            void *inClientData)
{

    printf( "default input device changed" );
    // check default input
    [ ( (__bridge  AppDelegate* ) inClientData ) listDevices ];

    return 0;
}


- ( void ) applicationDidFinishLaunching : ( NSNotification* ) aNotification
{

    defaults = [ NSUserDefaults standardUserDefaults ];
    
    itemsToIDS = [ NSMutableDictionary dictionary ];
    
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSInteger readenId = [prefs integerForKey: @"Device"];
    
    if (readenId == 0) {
        [prefs setInteger:UINT32_MAX forKey: @"Device"];
        [prefs synchronize];
    }
    
    forcedInputID = readenId;
    
    NSLog(@"Loaded device from UserDefaults: %d", forcedInputID);

    NSImage* image = [ NSImage imageNamed : @"airpods-icon" ];
    [ image setTemplate : YES ];

    statusItem = [ [ NSStatusBar systemStatusBar ] statusItemWithLength : NSVariableStatusItemLength ];
    [ statusItem setToolTip : @"AirPods Audio Quality & Battery Life Fixer" ];
    [ statusItem setImage : image ];

    // add listener for detecting when input device is changed

    AudioObjectPropertyAddress inputDeviceAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };

    AudioObjectAddPropertyListener(
        kAudioObjectSystemObject,
        &inputDeviceAddress,
        &callbackFunction,
        (__bridge  void* ) self );

   AudioObjectPropertyAddress runLoopAddress = {
        kAudioHardwarePropertyRunLoop,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };

    CFRunLoopRef runLoop = NULL;
    
    UInt32 size = sizeof(CFRunLoopRef);
    
    AudioObjectSetPropertyData(
        kAudioObjectSystemObject,
        &runLoopAddress,
        0,
        NULL,
        size,
        &runLoop);
    
     [ self listDevices ];
    
    // auto select item that name contains string "MacBook" and "Microphone"
    
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title containsString:@"MacBook"]) {
            if ([item.title containsString:@"Microphone"]) {
                [self deviceSelected:item];
            }
        }
    }
    
    [ statusItem setMenu : menu ];
}


- ( void ) deviceSelected : ( NSMenuItem* ) item
{

    NSNumber* number = itemsToIDS[ item.title ];
    
    if ( number != nil )
    {
    
        AudioDeviceID newId = [ number unsignedIntValue ];
        
        NSLog( @"switching to new device : %u" , newId );
        
        forcedInputID = newId;
        
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setInteger:newId forKey: @"Device"];
        [prefs synchronize];
        NSLog(@"Saved device from UserDefaults: %d", forcedInputID);

        UInt32 propertySize = sizeof(UInt32);
        AudioHardwareSetProperty(
            kAudioHardwarePropertyDefaultInputDevice ,
            propertySize ,
            &forcedInputID );
        
        // show forcing

        [ menu
            insertItemWithTitle : @"forcing..."
            action : NULL
            keyEquivalent : @""
            atIndex : 2 ];

    }
    
}


- ( void ) listDevices
{

    NSDictionary *bundleInfo = [ [ NSBundle mainBundle] infoDictionary];
    NSString *versionString = [ NSString stringWithFormat : @"Version %@ (build %@)",
                               bundleInfo[ @"CFBundleShortVersionString" ],
                               bundleInfo[ @"CFBundleVersion"] ];

    menu = [ [ NSMenu alloc ] init ];
    menu.delegate = self;
    [ menu addItemWithTitle : versionString action : nil keyEquivalent : @"" ];
    [ menu addItem : [ NSMenuItem separatorItem ] ]; // A thin grey line
    
    NSMenuItem* item =  [ menu
            addItemWithTitle : NSLocalizedString(@"Pause", @"Pause")
            action : @selector(manualPause:)
            keyEquivalent : @"" ];

    if ( paused ) [ item setState : NSControlStateValueOn ];

    [ menu addItem : [ NSMenuItem separatorItem ] ]; // A thin grey line
    [ menu addItemWithTitle : @"Forced input:" action : nil keyEquivalent : @"" ];
    
    UInt32 propertySize;
    
    AudioDeviceID dev_array[64];
    int numberOfDevices = 0;
    char deviceName[256];
    
    AudioHardwareGetPropertyInfo(
        kAudioHardwarePropertyDevices,
        &propertySize,
        NULL );
    
    AudioHardwareGetProperty(
        kAudioHardwarePropertyDevices,
        &propertySize,
        dev_array);
    
    numberOfDevices = ( propertySize / sizeof( AudioDeviceID ) );
    
    NSLog( @"devices found : %i" , numberOfDevices );
    
    if ( forcedInputID < UINT32_MAX )
    {
    
        char found = 0;

        for( int index = 0 ;
                 index < numberOfDevices ;
                 index++ )
        {
        
            if ( dev_array[ index] == forcedInputID ) found = 1;
        
        }
        
        if ( found == 0 )
        {
            NSLog( @"force input not found in device list" );
            forcedInputID = UINT32_MAX;
        }
        else NSLog( @"force input found in device list" );
        
    }


    for( int index = 0 ;
             index < numberOfDevices ;
             index++ )
    {
    
        AudioDeviceID oneDeviceID = dev_array[ index ];

        propertySize = 256;
        
        AudioDeviceGetPropertyInfo(
            oneDeviceID ,
            0 ,
            true ,
            kAudioDevicePropertyStreams ,
            &propertySize ,
            NULL );

        // if there are any input streams, then it is an input

        if ( propertySize > 0 )
        {
        
            // get name

            propertySize = 256;
            
            AudioDeviceGetProperty(
                oneDeviceID ,
                0 ,
                false ,
                kAudioDevicePropertyDeviceName ,
                &propertySize ,
                deviceName );

            NSLog( @"found input device : %s  %u\n" , deviceName , (unsigned int)oneDeviceID );
            
            NSString* nameStr = [ NSString stringWithUTF8String : deviceName ];

            if ( [ [ nameStr lowercaseString ] containsString : @"built" ] && forcedInputID == UINT32_MAX )
            {

                // if there is no forced device yet, select "built-in" by default

                NSLog( @"setting forced device : %s  %u\n" , deviceName , (unsigned int)oneDeviceID );

                forcedInputID = oneDeviceID;
                
            }

            NSMenuItem* item = [ menu
                addItemWithTitle : [ NSString stringWithUTF8String : deviceName ]
                action : @selector(deviceSelected:)
                keyEquivalent : @"" ];
            
            if ( oneDeviceID == forcedInputID )
            {
                [ item setState : NSControlStateValueOn ];
                NSLog( @"setting device selected : %s  %u\n" , deviceName , (unsigned int)oneDeviceID );
            }
            
            itemsToIDS[ nameStr ] = [ NSNumber numberWithUnsignedInt : oneDeviceID];

        }

        [ statusItem setMenu : menu ];

    }

    // get current input device
    
    AudioDeviceID deviceID = kAudioDeviceUnknown;

    // get the default output device
    // if it is not the built in, change
    
    propertySize = sizeof( deviceID );
    
    AudioHardwareGetProperty(
        kAudioHardwarePropertyDefaultInputDevice,
        &propertySize,
        &deviceID);
    
    NSLog( @"default input device is %u" , deviceID );
    
    if ( !paused && deviceID != forcedInputID )
    {

        NSLog( @"forcing input device for default : %u" , forcedInputID );

        UInt32 propertySize = sizeof(UInt32);
        AudioHardwareSetProperty(
            kAudioHardwarePropertyDefaultInputDevice ,
            propertySize ,
            &forcedInputID );
        
        // show forcing

        [ menu
            insertItemWithTitle : @"forcing..."
            action : NULL
            keyEquivalent : @""
            atIndex : 2 ];

    }
    
    [ menu addItem : [ NSMenuItem separatorItem ] ]; // A thin grey line

    startupItem = [ menu
        addItemWithTitle : @"Open at login"
        action : @selector(toggleStartupItem)
        keyEquivalent : @"" ];
    
    [ menu addItem : [ NSMenuItem separatorItem ] ]; // A thin grey line

    [ menu addItem : [ NSMenuItem separatorItem ] ]; // A thin grey line
    [ menu addItemWithTitle : @"Donate if you like the app"
           action : @selector(support)
           keyEquivalent : @"" ];

    [ menu addItemWithTitle : @"Check for updates"
           action : @selector(update)
           keyEquivalent : @"" ];
    
    [ menu addItemWithTitle : @"Hide"
           action : @selector(hide)
           keyEquivalent : @"" ];
    
    [ menu addItemWithTitle : @"Quit"
           action : @selector(terminate)
           keyEquivalent : @"" ];

}

- ( void ) manualPause : ( NSMenuItem* ) item
{
    paused = !paused;
    [ self listDevices ];
}

- ( void ) terminate
{
    [ NSApp terminate : nil ];
}

- ( void ) support
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://paypal.me/milgra"]];
}

- ( void ) update
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://milgra.com/airpods-sound-quality-fixer.html"]];
}

- ( void ) hide
{
    [statusItem setVisible:false];
}

- (void)toggleStartupItem
{
    if ( [GBLaunchAtLogin isLoginItem] )
    {
        [GBLaunchAtLogin removeAppFromLoginItems];
    }
    else
    {
        [GBLaunchAtLogin addAppAsLoginItem];
    }
    
    [self updateStartupItemState];
}

- (void)updateStartupItemState
{
    [startupItem setState: [GBLaunchAtLogin isLoginItem] ? NSControlStateValueOn : NSControlStateValueOff];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    [self updateStartupItemState];
}

@end
