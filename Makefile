THEOS ?= /Users/evan/theos
ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = TikTokBlocker
TikTokBlocker_FILES = Tweak.xm Preferences.m SettingsUI.xm
TikTokBlocker_CFLAGS = -fobjc-arc
TikTokBlocker_FRAMEWORKS = Foundation UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
