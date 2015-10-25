export GO_EASY_ON_ME = 1

export ARCHS = armv7 arm64
export SDKVERSION = 7.0
export TARGET = iphone:clang:latest:7.0

PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)
# THEOS_PACKAGE_DIR_NAME =

include $(THEOS)/makefiles/common.mk
# _THEOS_INTERNAL_CFLAGS += -w

TWEAK_NAME = Gmailer
Gmailer_FILES = Tweak.xm
# Gmailer_FRAMEWORKS = UIKit
# Gmailer_PRIVATE_FRAMEWORKS =
# Gmailer_LIBRARIES =
# Gmailer_CODESIGN_FLAGS = -SEntitlements.plist
# ADDITIONAL_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Gmailer
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
