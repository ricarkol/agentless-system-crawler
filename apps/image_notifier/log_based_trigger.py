import sys
import json
from pygtail import Pygtail

log_file='/var/log/docker-registry/access.log'
added_images = []
image_tags = {}
deleted_images = []
for line in Pygtail(log_file):
    if 'PUT' in line and 'tags' in line:
        put_index = line.find('"PUT') + len('"PUT /v1/repositories/')
        http_index = line.find('HTTP/')
        # lines with or without repository 
        # example 1: "daytrader_v2_nc/tags/latest",
        # example 2: "cloudsight/nilton-test/tags/latest",
        # separate image name and tag name
        line_with_image_and_tag = line[put_index:http_index].strip()
        tag_index_begin = line_with_image_and_tag.find('/tags/')
        tag_index_end = tag_index_begin + len('/tags/')
        image = line_with_image_and_tag[:tag_index_begin]
        tag = line_with_image_and_tag[tag_index_end:]
        added_images.append(image)
        image_tags[image] = tag
    elif 'DELETE' in line and 'repositories' in line:
        del_index = line.find('"DELETE') + len('"DELETE /v1/repositories/')
        http_index = line.find('HTTP/')
        image = line[del_index:http_index].strip()
        image = image [:-1]  # to strip last /
        # if image contains libreay, the default repository remove it
        if image.startswith('library/'):
            image = image[len('library/'):]
        deleted_images.append(image)

for image in deleted_images:
    try:
        added_images.remove(image)
    except ValueError, e:
        print 'image={} not in list'.format(image)

print json.dumps(added_images, indent=2)
print json.dumps(image_tags, indent=2)
