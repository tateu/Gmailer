include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Gmailer
Gmailer_FILES = Gmailer.xm
Gmailer_INSTALL_PATH = /Library/PreferenceBundles
Gmailer_FRAMEWORKS = UIKit
Gmailer_PRIVATE_FRAMEWORKS = Preferences
ADDITIONAL_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Gmailer.plist$(ECHO_END)
