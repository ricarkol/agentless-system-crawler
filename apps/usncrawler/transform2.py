import json
import argparse


def process_file(args):

    with open(args.usn_file, 'r') as rp:
        j = json.load(rp)
        j['id'] = j['secid']
        del j['secid']

    with open(args.usn_file, 'w') as wp:
        wp.write(json.dumps(j, indent=2))

if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--usn-file',  type=str, required=True, help='old usn file')
        args = parser.parse_args()
        process_file(args)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e) 

