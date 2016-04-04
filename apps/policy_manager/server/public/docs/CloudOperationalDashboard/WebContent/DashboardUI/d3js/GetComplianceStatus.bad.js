pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;




var selectedPlatform = "Redhat";
var numberOfActions = 0;

var currentIP = null;
var currentHostName = "To be Displayed";
var currentOSVersion = "";
var currentOS = "";
var arrayOfVMs = [];
var firstLoad= true;
var tableRef = null;
// var viewFlag=true;
$(document).ready(function() {
	console.log("Initializing Components");
	categoryToLoad = "All";

	getComplianceStatus()

});
function getComplianceStatus(containerID) {
	console.log("Getting image IDs ");

	$.ajax({
		type : 'GET',
		url : "https://kasa.sl.cloud9.ibm.com:9292/containers/" + containerID + "rules",
		dataType : "json", // data type of response
		success : showAllImages,
		fail:function() {   		
		}
	});
}

////https://kasa.sl.cloud9.ibm.com:9292/api/containers/AUzFZ9EErtZi7K2M44yJ/rules

function showAllImages(data) {

	var dataFound = false;
	var iTotalRecords = 0;
	var  iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';
	
	
	var flag = 0;
	$
			.each(
					data,
					function(object, Object) {

						console.log(Object.IPaddress);
						console.log(Object.OperatingSystem);
						console.log(Object.Category);

					

						var ipAddress = Object.IPaddress;
						var operatingSystem = Object.OperatingSystem;
						var category = Object.Category
						var hostname = Object.Hostname;
						var status = Object.Status;
						if(status==undefined){
							status = Object.status;
						}
						console.log("operatingSystem-"
								+ operatingSystem.toLowerCase());
						// Add option to managed VMs list
						if ((category == categoryToLoad || categoryToLoad == "All")
								&& (operatingSystem.toLowerCase().indexOf(
										selectedPlatform.toLowerCase()) >= 0)) {
							dataFound = true;
							if (status == "Scan_Failed"
									|| status == "Scan_Successful") {

								timeOfAction = Object.LastTimeOfAction;
								if (timeOfAction == null || timeOfAction == "") {
									timeOfAction = "Never scanned.";
								} else {
									var a = new Date(timeOfAction);
									var months = [ 'Jan', 'Feb', 'Mar', 'Apr',
											'May', 'Jun', 'Jul', 'Aug', 'Sep',
											'Oct', 'Nov', 'Dec' ];
									var year = a.getFullYear();
									var month = months[a.getMonth()];
									var date = a.getDate();
									var hour = addZero(a.getHours());
									var min = addZero(a.getMinutes());
									var sec = addZero(a.getSeconds());
									time = date + ',' + month + ' ' + year
											+ ' ' + hour + ':' + min + ':'
											+ sec;
									timeOfAction =  time;
								}

								flag++;

								var viewLink = "<div id="
										+ ipAddress
										+ "-view><a id="
										+ ipAddress
										+ " href=AMMViewLastScanResult.html?IPAddress="
										+ ipAddress + " >View</a></div>";

															
								var disable = "";

								if (timeOfAction == "Never scanned."
										|| timeOfAction == "Host was up-to-date. No patches were missing."
										|| status == null || status == ""
										|| status == "In_Progress") {
							
									
									viewLink = "<div id="
										+ ipAddress
										+ "-view><lable>View</lable></div>";
									
								}

								var timeLink = "<div id=" + ipAddress
										+ "-time>" + timeOfAction
										+ "</div>";

								iTotalRecords++;
								iTotalDisplayRecords++;
													
								
								data1 = data1+ '{"IPaddress":'+'"'+ipAddress+'"'+  ",";
								data1 = data1+ '"fqdn":'+'"'+hostname+'"'+  ",";
								data1 = data1+ '"Category":'+'"'+category+'"'+  ",";
								data1 = data1+ '"OS":'+'"'+operatingSystem+'"'+  ",";
								data1 = data1+ '"lastScan":'+'"'+timeLink+'"'+  ",";
								data1 = data1+ '"result":'+'"'+viewLink+'"'+  "},";
								
						
							}
						}

					});
	
	if(dataFound){
    	data1 = data1.slice( 0, data1.lastIndexOf( "," ) ) + data1.substring( data1.lastIndexOf( "," )+1 );
    }
	
    data1 = data1 + "]}";

   console.log("Patch:"+data1);
   var da = JSON.parse(data1);
   
   da.iTotalRecords = iTotalRecords;
   da.iTotalDisplayRecords = iTotalDisplayRecords;
 
   

	//data = jQuery.parseJSON(data);
	
	console.log("da.aaData.length "+da.aaData);
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
		
	var ops = fillCategoryBoxOptions(categoryToLoad);
	$("#categorySelect").html(ops);

}
