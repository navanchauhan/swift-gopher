#!/bin/bash

mkdir -p docs/

for target in "$@"
do
    echo "Generating docs for $target"
    swift package --allow-writing-to-directory "$target-docs" generate-documentation --disable-indexing --transform-for-static-hosting --hosting-base-path swift-gopher --output-path "$target-docs" --target "$target"
    cp -r $target-docs/* docs/
    modified_target=$(echo $target | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    cp -r $target-docs/index/index.json "docs/index/$modified_target.json"
done

echo "<!DOCTYPE html><html><head></head><body><ol>" > docs/index.html

for target in "$@"
do
    cp -R $target-docs/data/documentation/* docs/data/documentation/
    cp -R $target-docs/documentation/* docs/documentation/
    rm -r "$target-docs"
    modified_target=$(echo $target | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    echo "<li><a href=\"/swift-gopher/documentation/$modified_target/\">$target</a></li>" >> docs/index.html
done

echo "</ol></body></html>" >> docs/index.html

custom_javascript="window.location.pathname.split('documentation/')[1].split('/')[0]"
file_to_modify=$(ls docs/js/documentation-topic\~topic\~tutorials-overview.*.js)

sed  -i '' 's/"index.json"/window.location.pathname.split("documentation\/")[1].split("\/")[0]+".json"/g' $file_to_modify
echo "Modified $file_to_modify"
