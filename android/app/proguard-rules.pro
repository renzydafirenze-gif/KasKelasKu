# SQLCipher 4.x resolves these classes/methods by name from JNI_OnLoad.
# R8 renaming causes release-only native abort before login.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
