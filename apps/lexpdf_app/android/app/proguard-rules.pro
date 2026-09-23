# LexPDF instantiates TextRecognizer only with TextRecognitionScript.latin.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**


# OkHttp treats Conscrypt as an optional TLS provider. Apryse consumer rules
# already preserve its own SDK; suppress only the optional provider references
# so R8 does not reject release builds when Conscrypt is intentionally absent.
-dontwarn org.conscrypt.**
