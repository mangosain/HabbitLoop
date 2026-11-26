#!/usr/bin/env python3
"""Idempotently update generated Android native files for flutter_local_notifications.
Run from mobile project root *after* flutter create --platforms=android,ios .
Supports Flutter's Kotlin Gradle and legacy Groovy Gradle files.
"""
from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
manifest=root/'android/app/src/main/AndroidManifest.xml'
if not manifest.exists():
    sys.exit('Android project missing. Run flutter create --platforms=android,ios . first.')
s=manifest.read_text()
for permission in ('POST_NOTIFICATIONS','RECEIVE_BOOT_COMPLETED'):
    line=f'    <uses-permission android:name="android.permission.{permission}" />'
    if f'android.permission.{permission}' not in s:
        s=s.replace('<application',line+'\n    <application',1)
receivers='''        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''
if 'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver' not in s:
    s=s.replace('</application>',receivers+'    </application>',1)
manifest.write_text(s)

kts=root/'android/app/build.gradle.kts'
groovy=root/'android/app/build.gradle'
file=kts if kts.exists() else groovy
if not file.exists():sys.exit('Android app Gradle configuration missing.')
g=file.read_text()
if file.suffix=='.kts':
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g=re.sub(r'(compileOptions\s*\{)',r'\1\n        isCoreLibraryDesugaringEnabled = true',g,count=1)
    if 'desugar_jdk_libs' not in g:
        g+='\n// Required by flutter_local_notifications for scheduled notifications.\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
else:
    if 'coreLibraryDesugaringEnabled' not in g:
        g=re.sub(r'(compileOptions\s*\{)',r'\1\n        coreLibraryDesugaringEnabled true',g,count=1)
    if 'desugar_jdk_libs' not in g:
        g+='\n// Required by flutter_local_notifications.\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
file.write_text(g)
print('Configured Android notification permissions, receivers, and core library desugaring.')
