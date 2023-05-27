:: Assumes running from LanguageTracker\build
mkdir out\LanguageTracker
copy ..\extension.xml out\LanguageTracker\
copy ..\readme.txt out\LanguageTracker\
copy ..\"Open Gaming License v1.0a.txt" out\LanguageTracker\
mkdir out\LanguageTracker\graphics\icons
copy ..\graphics\icons\languagetracker_icon.png out\LanguageTracker\graphics\icons\
mkdir out\LanguageTracker\scripts
copy ..\scripts\languagetracker.lua out\LanguageTracker\scripts\
cd out
CALL ..\zip-items LanguageTracker
rmdir /S /Q LanguageTracker\
copy LanguageTracker.zip LanguageTracker.ext
cd ..
explorer .\out
