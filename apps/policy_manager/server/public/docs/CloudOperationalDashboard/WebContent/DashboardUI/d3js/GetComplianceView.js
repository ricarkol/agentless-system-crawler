
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var images = {};
var compliance_status = "";

$(document).ready(function(){
	buildTable();
	getImages();
	
	//for (var id in images) {
		//console.log(images[id]);
	//}
	
});


function buildTable(){
	
	tableRef = $("#dtable").dataTable({    
		"aoColumns": [       
		              		{"mData": "image_id" },      
		              		{"mData": "image_name"},      
		              		{"mData": "checking_ts"},      
		              		{"mData": "compliance_status"} 
		              ],
			"paging": false,
		    "aData": null,
		    "scrollY":        "350px",
		    "order": [[ 2, "asc" ]],
			"scrollCollapse": false,
			"oLanguage": {
					   "sEmptyTable":     "No records found",
					   "sLoadingRecords": "Loading...",
					   "sProcessing": "DataTables is currently busy"
					   },			

				   "dom": '<"row" <"col-lg-4"<"upper-left">><"col-lg-6 text-center"lf><"col-lg-2"<"upper-right text-right">>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
		});
	
	   $("div.upper-right").html('<button type="button" class="btn btn-default btn-md" style="padding-bottom: 9px; padding-top: 9px;" onclick="refresh()"><i class="fa fa-refresh"></i></button>');
	

}



function refresh(){
	   $("#errorDiv").removeClass("alert alert-danger alert-info");
       $("#errorDiv").empty();
       getImages();
}


function showImageStatus() {

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();
	
	$.ajax({
		type : 'GET',
		url : "https://kasa.sl.cloud9.ibm.com:9292/api/containers",
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});
	
}

function callShowResult(data) {

	//setLabels();

	var message = "No image available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data, function(object, Object) {

		if (data == "") {
			console.log(messge);
			message = "No image available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html(
					"<strong>Information. </strong>No image available.");
			flag = 1;

		} else if (data != null) {

			if (Object.Message != null) {
				message = Object.Message;
				console.log(message);
				$('#errorDiv').addClass("alert alert-danger");
				$('#errorDiv').html("<strong>Error. </strong>" + message);

				flag = 1;
			} else {
				dataFound = true;
				// flag = 0
				console.log("**** " + Object.id);

				var date = new Date(Object.created * 1000);
				if (Object.created == 0) {
					date = "-";
				}

				var tmp = images[Object.image_id];
				var image_id = "";
				var image_name = "";
				if (tmp != null){
					var output = JSON.parse(tmp);
					image_id = output.image_id;
					image_name = output.image_name;
					if (image_id.length > 15) {
						image_id = image_id.substring(0, 15) + "...";
					}
				}
				getComplianceStatus(Object.id);
				
				console.log(image_id);
				console.log(image_name);
				console.log(Object.created);
				console.log(Object.id);
				
				data1 = data1 + '{"image_id":' + '"' + image_id + '"' + ",";
				data1 = data1 + '"image_name":' + '"' + image_name
						+ '"' + ",";
				data1 = data1 + '"checking_ts":' + '"' + date+ '"' + ",";
				data1 = data1 + '"compliance_status":' + '"<a id=\''+Object.id+ '\'href=ComplianceStatusView.html?ContainerID=' + Object.id+'>' + compliance_status + '</a>"'+ "},";
				
			}

		}

	});
	console.log("data1 " + data1);

	if (dataFound) {
		data1 = data1.slice(0, data1.lastIndexOf(","))
				+ data1.substring(data1.lastIndexOf(",") + 1);
	}

	if (flag == 0 && !dataFound) {
		message = "No image available.";
		$('#errorDiv').addClass("alert alert-info");
		$('#errorDiv').html("<strong>Information </strong>No image available.");
	}

	data1 = data1 + "]}";

	console.log("compliance status:" + data1);
	var da = JSON.parse(data1);
	console.log("da- " + da);
	da.iTotalRecords = iTotalRecords;
	da.iTotalDisplayRecords = iTotalDisplayRecords;

	if (da.aaData.length) {
		tableRef.fnAddData(da.aaData);
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	} else {
		tableRef.fnClearTable();
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	}
	tableRef.fnDraw();

}

function getComplianceStatus(id) {
	console.log("container id=" + id);
	
	var status = "pass";
	$.ajax({
		type : 'GET',
		url : "https://kasa.sl.cloud9.ibm.com:9292/api/containers/" + id + "/compliance",
		dataType : "text", // data type of response
		contentType : "application/text",
		async : false,
		data : "",
		success : function(data) {
			compliance_status = data;
		},
		error : function(xhr, status, error) {
			$("#divErrorMessages").empty().append(status);
			$("#divErrorMessages").append(xhr.responseText);

			alert(xhr.responseText);
		}
	});
}


function getImages_kasa() {

	$.ajax({
		type : "GET",
		contentType : "application/json; charset=utf-8",
		url : 'https://kasa.sl.cloud9.ibm.com:9292/api/images',
		dataType : 'json',
		async : true,
		data : "{}",
		success : function(data) {
			$.each(data, function(idx, obj) {
				images[obj.id]='{"image_name":"' + obj.image_name + '","image_id":"' + obj.image_id + '"}';
			});
			showImageStatus();
		},
		error : function(xhr, status, error) {
			$("#divErrorMessages").empty().append(status);
			$("#divErrorMessages").append(xhr.responseText);

			alert(xhr.responseText);
		}
	});     	
}


function getImages() {

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();
	
	$.ajax({
		type : 'GET',
		url : "https://arthur.trl.ibm.com:9292/images/data",
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult_dev,

	});    	
}


function callShowResult_dev(data) {

	//setLabels();

	var message = "No image available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data, function(object, Object) {

		if (data == "") {
			console.log(messge);
			message = "No image available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html(
					"<strong>Information. </strong>No image available.");
			flag = 1;

		} else if (data != null) {

			if (Object.Message != null) {
				message = Object.Message;
				console.log(message);
				$('#errorDiv').addClass("alert alert-danger");
				$('#errorDiv').html("<strong>Error. </strong>" + message);

				flag = 1;
			} else {
				dataFound = true;
				// flag = 0
				console.log("**** " + Object.id);

				var date = new Date(Object.created * 1000);
				if (Object.created == 0) {
					date = "-";
				}

				var image_id = Object.image_id;
				var image_name = Object.image_name;
				if (image_id.length > 15) {
					image_id = image_id.substring(0, 15) + "...";
				}
				compliance_status = Object.compliance;
								
				console.log(image_id);
				console.log(image_name);
				console.log(Object.created);
				console.log(Object.id);
				
				data1 = data1 + '{"image_id":' + '"' + image_id + '"' + ",";
				data1 = data1 + '"image_name":' + '"' + image_name
						+ '"' + ",";
				data1 = data1 + '"checking_ts":' + '"' + date+ '"' + ",";
				data1 = data1 + '"compliance_status":' + '"<a id=\''+Object.id+ '\'href=ComplianceStatusView.html?ContainerID=' + Object.id+'>' + compliance_status + '</a>"'+ "},";
				
			}

		}

	});
	console.log("data1 " + data1);

	if (dataFound) {
		data1 = data1.slice(0, data1.lastIndexOf(","))
				+ data1.substring(data1.lastIndexOf(",") + 1);
	}

	if (flag == 0 && !dataFound) {
		message = "No image available.";
		$('#errorDiv').addClass("alert alert-info");
		$('#errorDiv').html("<strong>Information </strong>No image available.");
	}

	data1 = data1 + "]}";

	console.log("compliance status:" + data1);
	var da = JSON.parse(data1);
	console.log("da- " + da);
	da.iTotalRecords = iTotalRecords;
	da.iTotalDisplayRecords = iTotalDisplayRecords;

	if (da.aaData.length) {
		tableRef.fnAddData(da.aaData);
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	} else {
		tableRef.fnClearTable();
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	}
	tableRef.fnDraw();

}
