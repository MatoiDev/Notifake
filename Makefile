export ARCHS = arm64 arm64e armv7
export TARGET := iphone:clang:14.6:7.0
export SYSROOT = $(THEOS)/sdks/iPhoneOS14.5.sdk

INSTALL_TARGET_PROCESSES = SpringBoard


FINALPACKAGE=1
# DEBUG=1

# THEOS_PACKAGE_SCHEME=rootless

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	NotifakePreferences_INSTALL_PATH = /var/jb/Library/PreferenceBundles
    NotifakePreferences_RESOURCES_PATH = /var/jb/Library/PreferenceBundles/NotifakePreferences.bundle
    THEOS_DEVICE_IP = 192.168.1.35
else
    NotifakePreferences_INSTALL_PATH = /Library/PreferenceBundles
    THEOS_DEVICE_IP = 192.168.1.34
endif


TWEAK_NAME = Notifake

Notifake_FILES = Notifake.x
Notifake_CFLAGS = -fobjc-arc
Notifake_FRAMEWORKS = UIKit MobileCoreServices
Notifake_EXTRA_FRAMEWORKS += AltList
SUBPROJECTS += notifakepreferences

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

