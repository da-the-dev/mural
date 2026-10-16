// saver-start: ask the system to start the screen saver.
//
// Reverse-engineered from the Dock's -[HotCorners _postScreenSaverNotification:]
// (macOS 26.6.2): it posts a distributed notification
//
//     CFNotificationCenterPostNotification(
//         CFNotificationCenterGetDistributedCenter(),
//         CFSTR("com.apple.screensaver.action"),
//         /*object*/ NULL,
//         /*userInfo*/ CFDictionary{ CFSTR("action"): CFNumber(1) },
//         /*deliverImmediately*/ true);
//
// `loginwindow` observes it and starts the saver. The action value is 1
// (recovered from the Dock's start-saver handler, which calls
// -[HotCorners _postScreenSaverNotification:1]).
//
// With `askForPassword = 1` / `askForPasswordDelay = 0`, starting the saver also
// locks the Mac - which is the point: one action = custom lock-screen wallpaper
// + locked Mac.

import Foundation

let action = CommandLine.arguments.count > 1 ? (Int32(CommandLine.arguments[1]) ?? 1) : 1

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.apple.screensaver.action"),
    object: nil,
    userInfo: ["action": NSNumber(value: action)],
    deliverImmediately: true
)

// give the notification a moment to be delivered before we exit
Thread.sleep(forTimeInterval: 0.2)