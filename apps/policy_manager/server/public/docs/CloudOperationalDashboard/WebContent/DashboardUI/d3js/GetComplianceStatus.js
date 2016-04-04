var currentID;
pathArray = window.location.href.split('/');
queryParam = window.location.href.split("?");
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

$(document).ready(function(){
	buildTable();
	getParam ();
	showComplianceStatus(currentID);
});



function buildTable(){
	
	tableRef = $("#dtable").dataTable({    
		"aoColumns": [       
		              		{"mData": "id" },      
		              		{"mData": "description"},      
		              		{"mData": "status"},      
		              		{"mData": "reason"} 
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
       showComplianceStatus(currentID);
}



function getParam ()
{
	var containerID = "ContainerID";
	var params = queryParam[1].split("&");
	var sval = "";

	for (var i=0; i<params.length; i++)
	{
		temp = params[i].split("=");
		if ( [temp[0]] == containerID ) { 
			sval = temp[1]; 
			setcurrentID(temp[1]);

		}

	}
}


function showComplianceStatus(id) {
	//var vm = ip.split("#");
	console.log("container id=" + id);
	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();
	
	$.ajax({
		type : 'GET',
		url : "https://kasa.sl.cloud9.ibm.com:9292/api/containers/" + id + "/rules",
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});
	
}

function callShowResult(data) {

	//setLabels();

	var message = "No compliance checking results available.";

	var flag=0;
	 var dataFound = false;
	   var iTotalRecords = 0;
	   var  iTotalDisplayRecords = 0;
	   var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$
			.each(
					data,
					function(object, Object) {
							
						if (data == "") {
							console.log(messge);
							message = "No compliance checking results available.";
							$('#errorDiv').addClass("alert alert-info");
							$('#errorDiv').html("<strong>Information. </strong>No compliance checking results available.");
							flag = 1;
							
						} else if (data != null) {
							
							if (Object.Message != null) {
								message = Object.Message;
								console.log(message);
								$('#errorDiv').addClass("alert alert-danger");
								$('#errorDiv').html("<strong>Error. </strong>"+message);
						
								flag = 1;
							} else {
								dataFound = true;	
								// flag = 0
								 console.log("**** "+ Object.id);
                                 
                                 var last_output = Object.last_output;
                                 if (last_output.indexOf("data is not available in cloudsight") > -1){
                                         last_output = last_output.replace("data is not available in cloudsight: ", "")
                                 }
                                 
                                 var output = JSON.parse(last_output);

                                 var compliant = "unknown";
                                 if (output.compliant == "true") {
                                	 compliant = "pass";
                                 } else if (output.compliant == "false") {
                                	 compliant = "fail";
                                 }
                                 
                                 console.log(output.compliance_id);
                                 console.log(output.description);
                                 console.log(compliant);
                                 console.log(output.reason);

                                 data1 = data1+ '{"id":'+ '"'+output.compliance_id+'"'+",";
                                 data1 = data1+ '"description":'+'"'+output.description+'"'+  ",";
                                 data1 = data1+ '"status":'+'"'+compliant+'"'+  ",";
                                 data1 = data1+ '"reason":'+'"'+output.reason+'"'+  "},";

							}

						}

					});
	console.log("data1 "+data1);

	 if(dataFound){
	    	data1 = data1.slice( 0, data1.lastIndexOf( "," ) ) + data1.substring( data1.lastIndexOf( "," )+1 );
	    }
		
	 if(flag==0 && !dataFound){
		 message = "No compliance checking results available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html("<strong>Information </strong>No compliance checking results available.");
	 }
	 
	    data1 = data1 + "]}";
	
	   console.log("compliance status:"+data1);
	   var da = JSON.parse(data1);
	   console.log("da- "+da);
	   da.iTotalRecords = iTotalRecords;
	   da.iTotalDisplayRecords = iTotalDisplayRecords;

if (da.aaData.length){
	   tableRef.fnAddData(da.aaData);
	   var oFeatures = tableRef.fnSettings();
	   oFeatures.oLanguage.sEmptyTable = "No records found";
}
else
{
	   tableRef.fnClearTable();
	   var oFeatures = tableRef.fnSettings();
	   oFeatures.oLanguage.sEmptyTable = "No records found";
}
tableRef.fnDraw();

}

function setcurrentID(ipAddress){
	currentID = ipAddress;
}

function getcurrentID(){
	return currentID;
}

function okay(){
	window.location = "ComplianceView.html";
	
}

function setLabels() {

	var url = protocol + "/" + appContext
			+ "/jaxrs/patch/managedHosts/getmanagedVMs";

	console.log("URL:" + url);

	$
			.ajax({
				type : 'GET',
				url : url,
				dataType : "json", // data type of response
				async : false,
				success : function(data) {
					$
							.each(
									data,
									function(object, Object) {

										if (Object.IPaddress.indexOf(getcurrentID()) >= 0) {
											var hostname = Object.Hostname;
											var os = Object.OperatingSystem;
											var osArray = os.split(" ");
											var platform = osArray[0];
											var version = osArray[1];

											var category = Object.Category;
																												
											//$('#epDetails').html("<b>Scan Results</b><br/>IP Address:&nbsp&nbsp"+currentID+"<br/>OS:&nbsp&nbsp"+platform+"<br/>Host Name:&nbsp&nbsp"+hostname+"<br/>Version:&nbsp"+version+"<br/>Category:&nbsp&nbsp"+category);
																						
											$('#ipaddress').html("IP Address:&nbsp&nbsp"+currentID);
											$('#os').html("OS:&nbsp&nbsp"+platform);
											$('#hostname').html("Host Name:&nbsp&nbsp"+hostname);
											$('#version').html("Version:&nbsp"+version);
											$('#category').html("Category:&nbsp&nbsp"+category);
											
																				}
									});
				}
			});

}