set -x

dart run flutter_arb_translator:main --from en --to en_CA --service openai --dir D:\\Cloudmind\\BRiGHTPATH\\client\\lib\\l10n

if [ $? -ne 0 ]; then
    echo "Dude"
fi