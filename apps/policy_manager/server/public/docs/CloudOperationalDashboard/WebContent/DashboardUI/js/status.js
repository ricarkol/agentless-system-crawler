
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var selectTime = "";
var openid = "";
var tenant = "";

$(document).ready(function(){

	$.when(
  		setOpenId()
	).done(function() {
		setTopNavigator();
		buildDatetimepicker();
		buildTable();
		getStatus();
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


/** Rule group tree view ********************************************/


function buildDatetimepicker() {
	var now = new Date();
	selectTime = ISODateString(now);
	//console.log(selectTime);

	$('#datetimepicker').datetimepicker({
		format:'Y.m.d H:i',
  		lang:'en',

  		onClose: function(ct, $i) {
  			selectTime = ct.dateFormat('Y-m-d') + 'T' + ct.dateFormat('H:i:00-0000');
  			getStatus();
  		}
	});
}


function ISODateString(d){
 	function pad(n){return n<10 ? '0'+n : n}

 	return d.getUTCFullYear()+'-'
      	+ pad(d.getUTCMonth()+1)+'-'
	      + pad(d.getUTCDate())+'T'
	      + pad(d.getUTCHours())+':'
	      + pad(d.getUTCMinutes())+':'
	      + '00-0000'
}


function buildTable(){

	tableRef = $("#dtable").dataTable({
		
		"aoColumns": [       		              		
		    {"mData": "owner_namespace" },      
		    {"mData": "namespace"},      
		    {"mData": "registry"},
		    {"mData": "image_name"},
		    {"mData": "tag"},
		    {"mData": "crawl_time"},
		    {"mData": "vulnerability"},
		    {"mData": "noncompliance"}
		],


		"scrollY": 600,
        "scrollX": true,
		"paging": false,
		"aData": null,
		"order": [[ 1, "asc" ]],
		"scrollCollapse": false,

		"oLanguage": {
		   "sEmptyTable": "No records found",
		   "sLoadingRecords": "Loading...",
		   "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-8"<"upper-left">><"col-lg-4"<"upper-right text-right"lf>>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'	
	});

}


function callShowResult(data) {

	//setLabels();

	var message = "No data available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data, function(key, value) {

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

				data1 = data1 + '{"owner_namespace":' + '"' + value.owner_namespace + '"' + ",";
				data1 = data1 + '"namespace":' + '"' + value.namespace + '"' + ",";
				data1 = data1 + '"registry":' + '"' + value.registry + '"' + ",";
				data1 = data1 + '"image_name":' + '"' + value.image_name + '"' + ",";
				data1 = data1 + '"tag":' + '"' + value.tag + '"'+ ",";
				data1 = data1 + '"crawl_time":' + '"' + value.crawl_time + '"'+ ",";

				var vul = value.vulnerability;
				if(vul == null){
					data1 = data1 + '"vulnerability":' + '"null"'+ ",";
				}else{
					data1 = data1 + '"vulnerability":' + '"' + value.vulnerability.vulnerable_packages + "/" + value.vulnerability.total_packages + '"'+ ",";
				}

				var total = 0;
				var fail = 0;

				$.each(value.results, function(key, value) { 
					total++;
					if("Fail" == value){
						fail++;
					}
				});

				data1 = data1 + '"noncompliance":' + '"' + fail + "/" + total + '"},';
			}
		}

	});
	//console.log("data1 " + data1);

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

	//console.log("compliance status:" + data1);
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
	setClickEvent();

}


function setClickEvent() {

	$('#dtable > tbody > tr').on('click', 'td:eq(6)',  function () {
        $.cookie("namespace", $(this).prev().prev().prev().prev().prev().text());
        $.cookie("timestamp", $(this).prev().text());
        window.location.href = 'vulnerability.html';
    } );

	$('#dtable > tbody > tr').on('click', 'td:eq(7)',  function () {
        $.cookie("namespace", $(this).prev().prev().prev().prev().prev().prev().text());
        $.cookie("timestamp", $(this).prev().prev().text());
        window.location.href = 'noncompliance.html';
    } );
}


function changeFailColor() {

	$('#dtable > tbody > tr').each(function () {

		var vul_value = $(this).find(':nth-child(8)');
        if (!vul_value.text().startsWith("0/") ) {
        	vul_value.attr('class', 'fail');
        }

        var comp_value = $(this).find(':nth-child(7)');
        if (!comp_value.text().startsWith("0/") ) {
        	comp_value.attr('class', 'fail');
        }
    });
}


function getStatus() {

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	var url = protocol + "/api/services/get_result_page?openid=" + openid;

	//console.log(url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});    	

}

