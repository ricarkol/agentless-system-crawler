from flask import Flask, current_app, g, request, jsonify, abort, make_response, redirect, url_for, render_template
import os
import rest_endpoint_handler

template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../templates')
static_dir =  os.path.join(os.path.dirname(os.path.abspath(__file__)), '../static')
app = Flask(__name__, template_folder=template_dir, static_folder=static_dir)

######################
# REST API 
######################

@app.route("/")
def index():
    return redirect(url_for('welcome'))

@app.route("/welcome/")
def welcome():
    return current_app.handler.get_welcome()

@app.route("/tm_app", methods=["GET"])
def timemachine_app():
    try:
        return current_app.handler.timemachine_app()
    except Exception, e:
        print e

@app.route("/v0/bookmarks", methods=["GET"])
def get_bookmark():
    return current_app.handler.get_bookmarks(request.args)

@app.route("/v0/bookmark/<doc_id>", methods=["DELETE"])
def delete_bookmark(doc_id=None):
    return current_app.handler.delete_bookmark(doc_id)

@app.route("/v0/bookmark", methods=["POST"])
def create_bookmark():
    return current_app.handler.create_bookmark(request)

@app.route("/v0/bookmark/diff", methods=["GET"])
def diff_bookmark():
    return current_app.handler.diff_bookmark(request)

@app.route("/v0/diff_report_app")
def diff_report_app():
    return current_app.handler.diff_report_app()

@app.route("/v0/namespaces")
def get_namespaces():
    return current_app.handler.get_namespaces(request.args)

@app.route('/v0/config/frame/')
def get_config_frame():
    return current_app.handler.get_config_frame(request.args)

@app.route('/v0/config/frame/diff')
def get_config_frame_diff():
    return current_app.handler.get_config_frame_diff(request.args)

@app.route('/v0/config/frame/diff_report')
def get_config_frame_diff_report():
    return current_app.handler.get_config_frame_diff_report(request.args)

######################
# End of REST API 
######################

def main(args):
    app.handler = rest_endpoint_handler.RestEndpointHandler(args)
    #app.debug = True
    app.run(host='0.0.0.0', port=args.port)
