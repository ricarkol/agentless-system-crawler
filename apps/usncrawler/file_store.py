from __future__ import print_function
import json
import os

class FileStore(object):

    def __init__(self, repo_dir):
        self.repo_dir = repo_dir

    def store_sec_notice_list(self, sec_notice_list, logger):

        if not os.path.exists(self.repo_dir):
            try:
                os.mkdir(self.repo_dir)
            except Exception, e:
                logger.error(e)
                raise e

        for item in sec_notice_list:
            secid = item['id']
            logger.info ('storing id={}'.format(secid))
            sec_file_path = os.path.join(self.repo_dir, secid)
            if not os.path.exists(sec_file_path):
                with open(sec_file_path, 'w') as fp:
                    fp.write(json.dumps(item, indent=2))
        logger.info ('storing to local repo completed')
        return True

    def get_all_usn(self, logger):

        results = []
        if os.path.exists(self.repo_dir):
            for root, dirs, files in os.walk(self.repo_dir):
                for name in files:
                    try:
                        results.append(json.load(open(os.path.join(root, name))))
                    except Exception, e:
                        logger.error (e)
                        raise e
        return results
