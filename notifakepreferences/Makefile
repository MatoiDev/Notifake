BUNDLE_NAME = NotifakePreferences

FINALPACKAGE=1
# THEOS_PACKAGE_SCHEME=rootless

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	NotifakePreferences_INSTALL_PATH = /var/jb/Library/PreferenceBundles
    NotifakePreferences_RESOURCES_PATH = /var/jb/Library/PreferenceBundles/NotifakePreferences.bundle
else
    NotifakePreferences_INSTALL_PATH = /Library/PreferenceBundles
endif


NotifakePreferences_FILES = $(wildcard *.m) $(wildcard ../SupportLibraries/lottie/*.m)
NotifakePreferences_FRAMEWORKS = UIKit MobileCoreServices
NotifakePreferences_PRIVATE_FRAMEWORKS = Preferences

NotifakePreferences_CFLAGS = -fobjc-arc
NotifakePreferences_EXTRA_FRAMEWORKS = AltList

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk