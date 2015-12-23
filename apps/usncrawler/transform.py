import json
import argparse


def process_file(args):

    with open(args.usn_file, 'r') as rp:
        j = json.load(rp)
        j['site'] = j ['url']
        del j['url']
        j['id'] = j['usnid']
        del j['usnid']
        j['fixes'] = j['fixdata']
        del j['fixdata']

        for fix in j['fixes']:
            os = {'version': fix['distroversion'], 'distribution': '', 'name': 'ubuntu', 'architecture' : ''}
            fix['os'] = os
            del fix['distroversion']

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

