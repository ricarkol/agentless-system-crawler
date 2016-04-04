
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var selectedNameSpace = "";
var selectedTime = "";
var myplot;
var desidence; //Timezone of selected timestamp

var openid = "";
var tenant = "";

$(document).ready(function(){

	$.when(
  		setOpenId()
	).done(function() {
		setTopNavigator();

		buildTable();
		
		if ($.cookie("namespace") != null) {
			selectedNameSpace = $.cookie("namespace");
			//$.removeCookie("namespace");
			selectedTime = $.cookie("timestamp");
			//$.removeCookie("timestamp");

			getVulnerability();
		}
	});
	
});


/** Top Navigation *******************************************************/

function setTopNavigator(){
	$("#logout").on('click',function(event){
        event.preventDefault();
        event.stopPropagation();

        $.removeCookie("openid");
        $.removeCookie("tenant");
		$.removeCookie("namespace");
		$.removeCookie("timestamp");

        window.location.href = 'login.html';
	});

	$("#hellotxt").html("Hello <b>" + openid + "</b>");

	if(openid == "ibm_admin"){
		$("#tenantdd").removeClass("hidden");
		$("#sidebar li").removeClass("hidden");

		tenant = $.cookie("tenant");
		if(tenant != null){
			$("#tenantdd > a > b").text(tenant);
		}

		var url = protocol + "/api/tenants?openid=" + openid;

		$.ajax({
			type : 'GET',
			url : url,
			dataType : "json", 
			contentType : "application/json",
			success : function(data){
				$.each(data, function(i){
					$("#tenantdd ul").append('<li><a href="#"> ' + data[i].name + '</a></li>');
				})

				$("#tenantdd ul li a").on("click", function(event){
					var selectedTenant = $(this).text();
					$(this).parents().find("a > b").text(selectedTenant);

					$.cookie("tenant", selectedTenant);
				});
			},
			error : function(xhr, status, error) {
					console.log(status);
			}
		});    	
	}
}


function setOpenId(){
	var dfd = $.Deferred();

	openid = $.cookie("openid");

	if(openid == null){
	  	window.location.href = 'login.html';
	  	dfd.reject();
	} else {
		dfd.resolve();
	}

	return dfd.promise();
}


/* Table *********************************************************************/

function buildTable(){

	tableRef = $("#dtable").dataTable({
		
		"aoColumns": [       		              		
		    {"mData": "comp_id"},     
		    {"mData": "comp_desc" },      
		    {"mData": "comp"},    
		    {"mData": "reason"},
		],

		"columnDefs": [
    		{ "width": "10%", "targets": 0 },
    		{ "width": "40%", "targets": 1 },
    		{ "width": "10%", "targets": 2 },
 		],

		"scrollY": 450,
        "scrollX": true,
		"paging": false,
		"aData": null,
		"order": [[ 1, "desc" ]],
		"scrollCollapse": false,

		"oLanguage": {
		   "sEmptyTable": "No records found",
		   "sLoadingRecords": "Loading...",
		   "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-6"<"upper-left">><"col-lg-6"<"upper-right text-right"lf>>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
	});

}


function getVulnerability() {

	var url = protocol + "/api/services/get_result?openid=" + openid + "&namespace=" + encodeURIComponent(selectedNameSpace);

	url = url + "&timestamp=" + encodeURIComponent(selectedTime);

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	//console.log(url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});

}


function callShowResult(data) {

	$("#namespace-dd").text(selectedNameSpace);
	$("#timestamp-dd").text(selectedTime);
	//$("#rurl-dd").text("?");

	var message = "No data available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data.compliance.summary, function(key, value) {

		if (data == "") {
			console.log(messge);
			message = "No data available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html(
					"<strong>Information. </strong>No rule available.");
			flag = 1;

		} else if (data != null) {

			if (value.Message != null) {
				message = value.Message;
				console.log(message);
				$('#errorDiv').addClass("alert alert-danger");
				$('#errorDiv').html("<strong>Error. </strong>" + message);

				flag = 1;
			} else {
				dataFound = true;

				data1 = data1 + '{"comp_id":"' + key + '",';
				data1 = data1 + '"comp_desc":"' + value.description + '",';
				data1 = data1 + '"comp":"' + value.result + '",';
				data1 = data1 + '"reason":"' + value.reason + '"},';
			}
		}
	});

	if (dataFound) {
		data1 = data1.slice(0, data1.lastIndexOf(","))
				+ data1.substring(data1.lastIndexOf(",") + 1);
	}

	if (flag == 0 && !dataFound) {
		message = "No rule available.";
		$('#errorDiv').addClass("alert alert-info");
		$('#errorDiv').html("<strong>Information </strong>No data available.");
	}

	data1 = data1 + "]}";

	//console.log(data1);

	var da = JSON.parse(data1);
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
	changeFailColor();
}

function changeFailColor() {

	$('#dtable > tbody > tr').each(function () {

		var vul_value = $(this).find(':nth-child(3)');
        if (vul_value.text() == "FAIL" || vul_value.text() == "Fail" ) {
        	vul_value.attr('class', 'fail');
        }
    });
	
}


