from flask import Flask, current_app, g, request, jsonify, abort, make_response, redirect, url_for, render_template
import os
import rest_endpoint_handler
import search.cli.config

def setup_app_for_debugging():
    '''
      This function is only called if we start the service through this module, which is not how it
    is intended to be. We allow it just as a convenient way to start the service from an IDE such as Eclipse. 
    '''
    import logging
    
    logger = logging.getLogger("elk_cloudsight.search")
    logger.setLevel(logging.DEBUG)
     
    # create console handler
    handler = logging.StreamHandler()
    
    # create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s: %(message)s')
    
    # add formatter to handler
    handler.setFormatter(formatter)
    
    # add handler to logger
    logger.addHandler(handler)
    handler.setLevel(logging.DEBUG)

template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../templates')
static_dir =  os.path.join(os.path.dirname(os.path.abspath(__file__)), '../static')
app = Flask(__name__, template_folder=template_dir, static_folder=static_dir)

def setup_app(config, debug):
    setup_app_for_debugging()
    app.handler = rest_endpoint_handler.RestEndpointHandler(config)
    app.debug = debug

######################
# REST API 
######################

@app.route("/")
def index():
    return redirect(url_for('welcome'))

@app.route("/welcome/")
def welcome():
    return current_app.handler.get_welcome()

@app.route("/diff_report_app")
def diff_report_app():
    return current_app.handler.diff_report_app()

@app.route('/namespace_diff_report_app')
def namespace_diff_report_app():
    return current_app.handler.namespace_diff_report_app()

@app.route("/document", methods=["POST"])
def index_document():
    return current_app.handler.index_document(request)

@app.route("/document/<index>/<doctype>/<docid>", methods=["GET"])
def retrieve_document(index, doctype, docid):
    return current_app.handler.retrieve_document(index, doctype, docid)

@app.route("/namespaces")
def get_namespaces():
    return current_app.handler.get_namespaces(request.args)

@app.route('/config/frame')
def get_config_frame():
    return current_app.handler.get_config_frame(request.args)

@app.route('/config/frames')
def get_config_frames():
    return current_app.handler.get_config_frames(request.args)

@app.route('/config/frame/diff')
def get_config_frame_diff():
    return current_app.handler.get_config_frame_diff(request.args)

@app.route('/config/frame/diff_for_ui')
def get_config_frame_diff_for_ui():
    return current_app.handler.get_config_frame_diff_for_ui(request.args)

@app.route('/config/frame/diff_report')
def get_config_frame_diff_report():
    return current_app.handler.get_config_frame_diff_report(request.args)

@app.route("/namespace/crawl_times")
def get_namespace_crawl_times():
    return current_app.handler.get_namespace_crawl_times(request.args)

@app.route('/namespace/diff')
def get_namespace_diff():
    return current_app.handler.get_namespace_diff(request.args)

@app.route('/namespace/diff_report')
def get_namespace_diff_report():
    return current_app.handler.get_namespace_diff_report(request.args)

######################
# End of REST API 
######################

def main(config=None, debug=False):
    app.handler = rest_endpoint_handler.RestEndpointHandler(config)
    app.debug = debug
    if config:
        app.run(host='0.0.0.0', port=config.get_port())
    else:
        app.run(host='0.0.0.0', port=search.cli.config.Config.DEFAULT_PORT)
     
###################
# This code below is here just as a convenient way to start/debug the service from an IDE such as Eclipse.
# The service should be started for real by running the bin/search script. 
if __name__ == '__main__':
    setup_app_for_debugging()
    main(debug=True)
