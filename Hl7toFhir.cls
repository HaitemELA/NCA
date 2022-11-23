Class NCA.Hl7toFhir2 Extends Ens.BusinessProcess [ ClassType = persistent ]
{

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pArr As Ens.Response) As %Status
{
	set tsc = $$$OK
	Set nhsNumber = ""
	Set LocalCode =  ""
	set pArr=##class(%ArrayOfDataTypes).%New()
	Set relationshipLKUP = "NCA.RelationShipCodes"

	// NHS Number / Local Code
	Set Count=pRequest.GetValueAt("PID:3(*)")
	For i=1:1:Count 
	{	
		If (pRequest.GetValueAt("PID:3("_i_").5")="NHS")
		   	{
			   	Set nhsNumber=(pRequest.GetValueAt("PID:3("_i_").1"))
			   	Set nhsAssigner=(pRequest.GetValueAt("PID:3("_i_").4"))
		   	}
		If (pRequest.GetValueAt("PID:3("_i_").5")="DN")
		   	{
			   	Set LocalCode=(pRequest.GetValueAt("PID:3("_i_").1"))
		   	}
	}

	if nhsNumber="" && LocalCode=""
	{
		quit $$$ERROR(5001,"The patient's NHS Number and Local code are missing within the Inbound HL7 message.")
	}

	do pArr.SetAt(nhsNumber, "NhsNumberContent.value")
	do pArr.SetAt( nhsAssigner, "NhsNumberAssigner.display")
	do pArr.SetAt(LocalCode, "LocalCode")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.5"), "prefixContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.1"), "nameContent.family")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.2"), "givenNameContent.given")

	// Gender LookUp:
	if pRequest.GetValueAt("PID:8") = "M"
	{
		do pArr.SetAt("male", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "F"
	{
		do pArr.SetAt("female", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "U"
	{
		do pArr.SetAt("unknown", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "I"
	{
		do pArr.SetAt("other", "resource.gender")
	}

	// Date of birth
	do pArr.SetAt($ZDT($ZDATEH(pRequest.GetValueAt("PID:7.1"),5),3), "resource.birthDate")

	// Patient address
	do pArr.SetAt(pRequest.GetValueAt("PID:11.1"), "addressLinesContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.3"), "addressContent.city")
	do pArr.SetAt( pRequest.GetValueAt("PID:11.5"), "addressContent.postalCode")

	// Deceased patient
	if pRequest.GetValueAt("PID:29") '= ""
	{
		set deceaseDay = $EXTRACT(pRequest.GetValueAt("PID:29"), 1, 8)
		set deceaseTime = $EXTRACT(pRequest.GetValueAt("PID:29"), 9, 10)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 11, 12)_":"
		set deceaseTime = deceaseTime_$EXTRACT(pRequest.GetValueAt("PID:29"), 13, 17)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 18, 19)

		do pArr.SetAt($ZDT($ZDATEH(deceaseDay,5),3)_"T"_deceaseTime, "resource.deceasedDateTime")
	}
	
	do pArr.SetAt(pRequest.GetValueAt("PID:11.1"), "addressLinesContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.3"), "addressContent.city")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.5"), "addressContent.postalCode")
	do pArr.SetAt(pRequest.GetValueAt("PID:13.1"), "phoneContent.value")
	do pArr.SetAt(pRequest.GetValueAt("PID:13.4"), "emailContent.value")

	// Next of Kin
	Set Cnt=pRequest.GetValueAt("NK1(*)")
	For j=1:1:Cnt
	{
		Set RelationShipCode = ##class(Ens.Util.FunctionSet).Lookup(relationshipLKUP, pRequest.GetValueAt("NK1("_j_"):3.1"), "$D", "$DE")
		do pArr.SetAt(RelationShipCode_j, "relationshipCodingCode.code"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.5"), "ContactprefixContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.2"), "ContactgivenNameContent.given"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.1"), "ContactnameContent.family"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):5"), "ContactphoneContent.value"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):6"), "ContactphoneBusinessContent.value"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.1"), "ContactAddressLinesContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.2"), "ContactAddressLinesOtherContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.3"), "ContactAddressLinesCityContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.4"), "ContactAddressLinesStateContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.5"), "ContactAddressContent.postalCode"_j)
	}

	set tsc = ..PatientResource(pArr) // Patient
	set tsc = ..GPPractitionerRoleResource() //GPPractitionerRole
	set tsc = ..PractitionerRoleResource() //PractitionerRole

	// Practitioner
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.10"), "PASLocal")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.1"), "NationalCode")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.2"), "GPFamilyName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.3"), "GPGivenName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.6"), "GPPrefix")

	set tsc = ..PractitionerResource(pArr)
	
	// Organization
	do pArr.SetAt(pRequest.GetValueAt("PD1:3.3"), "odsOrganisationCode")
	do pArr.SetAt(pRequest.GetValueAt("PD1:3.1"), "OrganisationName")
	set tsc = ..OrganizationResource(pArr)
	
	set tsc = ..LocationResource() // Location
	set tsc = ..EpisodeOfCareResource() //EpisodeOfCare
	set tsc = ..EncounterResource() // EncounterOutPatient

	// ServiceRequest
	do pArr.SetAt(pRequest.GetValueAt("RF1:2"), "SRstatus")
	do pArr.SetAt(pRequest.GetValueAt("RF1:10"), "SRcategoryText")
	set tsc = ..ServiceRequestResource(pArr) // EncounterOutPatient


	;$$$TRACE("pArr.Count(): "_pArr.Count())

	quit tsc
}

// Patient Resource

Method PatientResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK

	set nhsNumber = pArr.GetAt("NhsNumberContent.value")
	set nhsAssigner = pArr.GetAt("NhsNumberAssigner.display") 
	set LocalCode = pArr.GetAt("LocalCode")
	// Create a new resource
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the resource
	set resource.resourceType = "Patient"

	// NHS Number
	set identifierArray = ##class(%DynamicArray).%New()
	if nhsNumber
	{
		set NhsNumberContent = ##class(%DynamicObject).%New()
		Set NhsNumberAssigner = ##class(%DynamicObject).%New()
		set NhsNumberContent.system = "https://fhir.nhs.uk/Id/nhs-number"
		set NhsNumberContent.value = nhsNumber
		set NhsNumberAssigner.display = nhsAssigner
		set NhsNumberContent.assigner = NhsNumberAssigner

		do identifierArray.%Push(NhsNumberContent)
	}
	
	//ODS-Local: skip if the inbound HL7 doesn't have it
	if LocalCode
	{
		set LocalContent = ##class(%DynamicObject).%New()
		Set LocalAssigner = ##class(%DynamicObject).%New()
		set LocalContent.system = "ODS-Local"
		set LocalContent.value = LocalCode
		;set LocalAssigner.reference = "https://fhir.hl7.org.uk/StructureDefinition/UKCore-Organization"
		set LocalAssigner.display = "PAS-LOCAL"
		set LocalContent.assigner = LocalAssigner

		do identifierArray.%Push(LocalContent)
	}

	// push both identifiers: NHS Number + Local Code
	set resource.identifier = identifierArray

	// Name
	set nameArray = ##class(%DynamicArray).%New()
	set nameContent = ##class(%DynamicObject).%New()
	set nameContent.use = "official"
	
	Set prefixArray = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	Set prefixContent = ##class(%DynamicArray).%New()
	set prefixContent = pArr.GetAt("prefixContent")
	set prefixArray.prefix  = prefixContent
	set nameContent.prefix = prefixArray

	set nameContent.family = pArr.GetAt("nameContent.family")

	Set givenNameContent = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	set givenNameContent.given = pArr.GetAt("givenNameContent.given")
	set nameContent.given = givenNameContent

	do nameArray.%Push(nameContent)
	set resource.name = nameArray

	// If old name exists, then apply the same process

	// Gender
	set resource.gender = pArr.GetAt("resource.gender")

	// BirthDate
	set resource.birthDate = pArr.GetAt("resource.birthDate")

	//Deceased
	;set resource.deceasedBoolean = "true"
	if pArr.GetAt("resource.deceasedDateTime") '= ""
	{
		set resource.deceasedDateTime = pArr.GetAt("resource.deceasedDateTime")
	}

	//maritalStatus
	Set maritalStatus = ##class(%DynamicObject).%New()

	set tsc = ..CodebaleConcept("http://terminology.hl7.org/CodeSystem/v3-MaritalStatus", "M", "Married", .maritalSt, .DynObject)
	set resource.maritalStatus = maritalSt

	// Address
	set addressArray = ##class(%DynamicArray).%New()
	set addressContent = ##class(%DynamicObject).%New()

	set addressLinesArray = ##class(%DynamicArray).%New() // for address lines
	set addressLinesContent = ##class(%DynamicArray).%New()
	set addressLinesContent = pArr.GetAt("addressLinesContent")
	set addressLinesArray.line = addressLinesContent // Loop HL7 for address lines
	set addressContent.line = addressLinesArray

	set addressContent.city = pArr.GetAt("addressContent.city")
	set addressContent.postalCode = pArr.GetAt("addressContent.postalCode")
    set addressContent.country = "UK"

	do addressArray.%Push(addressContent)
	set resource.address = addressArray

	//telecom
	set telecomArray = ##class(%DynamicArray).%New()
	set phoneContent = ##class(%DynamicObject).%New()
	
	if pArr.GetAt("phoneContent.value") '= ""
	{
		set phoneContent.system = "phone"
		set phoneContent.value = pArr.GetAt("phoneContent.value")
		set phoneContent.use = "home"
		do telecomArray.%Push(phoneContent)
	}

	if pArr.GetAt("emailContent.value") '= ""
	{
		set emailContent = ##class(%DynamicObject).%New()
		set emailContent.system = "email"
		set emailContent.value = pArr.GetAt("emailContent.value")
		set emailContent.use = "work"
		do telecomArray.%Push(emailContent)

	}

	set resource.telecom = telecomArray

	// Contact
	
	set ContactContentArray  = ##class(%DynamicArray).%New()

	set j=1
	while pArr.GetAt("relationshipCodingCode.code"_j) '= ""
	{
		set ContactContent  = ##class(%DynamicObject).%New()
		set CodeArray = ##class(%DynamicArray).%New()
		set relationshipArray = ##class(%DynamicArray).%New()
		set relationshipCoding = ##class(%DynamicObject).%New()
		set relationshipCodingCode = ##class(%DynamicObject).%New()

		set ContactnameContent = ##class(%DynamicObject).%New()
		Set ContactprefixArray = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array

		set ContacttelecomArray = ##class(%DynamicArray).%New()
		set ContactphoneContent = ##class(%DynamicObject).%New()

		set ContactAddressContent = ##class(%DynamicObject).%New()
		set ContactAddressLinesArray = ##class(%DynamicArray).%New() // for address lines

		set relationshipCodingCode.code = pArr.GetAt("relationshipCodingCode.code"_j)
		do CodeArray.%Push(relationshipCodingCode)
		set relationshipCoding.coding = CodeArray
		do relationshipArray.%Push(relationshipCoding)
		set ContactContent.relationship = relationshipArray

		set ContactprefixArray.prefix  = pArr.GetAt("ContactprefixContent"_j)
		set ContactnameContent.prefix = ContactprefixArray
		set ContactnameContent.given = pArr.GetAt("ContactgivenNameContent.given"_j)
		set ContactnameContent.family = pArr.GetAt("ContactnameContent.family"_j)
		set ContactContent.name = ContactnameContent

		set ContactphoneContent.system = "phone"
		set ContactphoneContent.value = pArr.GetAt("ContactphoneContent.value"_j)
		if ($EXTRACT(ContactphoneContent.value, 1, 2) = "07") || ($EXTRACT(ContactphoneContent.value, 1, 4) = "+447")
		{
			set ContactphoneContent.use = "mobile"
		}
		else
		{
			set ContactphoneContent.use = "home"
		}
		
		do ContacttelecomArray.%Push(ContactphoneContent)
		set ContactContent.telecom = ContacttelecomArray

		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesContent"_j))
		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesOtherContent"_j))
		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesCityContent"_j))

		if pArr.GetAt("ContactAddressLinesStateContent"_j) '= ""
		{
			do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesStateContent"_j))
		}
		
		set ContactAddressContent.line = ContactAddressLinesArray

		;set ContactAddressContent.city = pArr.GetAt("ContactAddressLinesCityContent"_j)
		set ContactAddressContent.postalCode = pArr.GetAt("ContactAddressContent.postalCode"_j)
		set ContactContent.address = ContactAddressContent

		do ContactContentArray.%Push(ContactContent)

		Set j = j+1
	}

	set resource.contact = ContactContentArray

	//Extension
	Set Extension = ##class(%DynamicArray).%New()

	// Extension - BirthPlace
	set birthPlace  = ##class(%DynamicObject).%New()
	set birthPlace.url = "http://hl7.org/fhir/StructureDefinition/patient-birthPlace"
	set birthPlace.value = "Birth Place" // !!!! need to be address type???

	do Extension.%Push(birthPlace)

	//Extension - Comments
	set commentsExtension  = ##class(%DynamicObject).%New()
	set commentsExtension.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/PatientComments"
	set commentsExtension.value= "This is a comment"
	do Extension.%Push(commentsExtension)

	// Extension - ethnicCategory
	set ethnicCategory = ##class(%DynamicObject).%New()
	set ethnicCategory.url = "https://fhir.hl7.org.uk/StructureDefinition/Extension-UKCore-EthnicCategory" //!!! this link will import ethnic categories from wales and
	// and scotland as well!! Need to use england codes only?  "https://fhir.hl7.org.uk/CodeSystem/UKCore-EthnicCategoryEngland"
	set ethnicCategory.value = "Ethnicity"

	do Extension.%Push(ethnicCategory)

	// Extension - patientReligion
	set patientReligion = ##class(%DynamicObject).%New()
	set patientReligion.url = "http://hl7.org/fhir/StructureDefinition/patient-religion"
	set patientReligion.value = "Religion Code"

	do Extension.%Push(patientReligion)

	//Extension - Nationality
	set Nationality = ##class(%DynamicObject).%New()
	set Nationality.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientNationality"
	set Nationality.value = "AF"

	do Extension.%Push(Nationality)

	//Extension - Occupation
	set Occupation = ##class(%DynamicObject).%New()
	set Occupation.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientOccupation"
	set Occupation.value = "Nurse"

	do Extension.%Push(Occupation)

	//Extension - School
	set School = ##class(%DynamicObject).%New()
	set School.type = "edu"
	set School.name = "School name"
	set School.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientSchool"

	do Extension.%Push(School)

	//GP
	set gpArray = ##class(%DynamicArray).%New()
	set gpContent  = ##class(%DynamicObject).%New()
	set gpContent.reference = "Practitioner/practitioner1"
	do gpArray.%Push(gpContent)

	set resource.generalPractitioner = gpArray
	
	//UKCore extensions
	set resource.extension = Extension
	zw resource
	$$$TRACE("Patientresource= "_resource.%ToJSON())

	// Add the resource into a streamContainer	
	/*
	set stream=##class(%Stream.GlobalCharacter).%New()
	set string = resource.%ToJSON()
	set tsc = stream.WriteLine(string)
	set strmCont=##class(Ens.StreamContainer).%New()
	set strmCont.Stream=stream
	*/

	// Consent resource
	if nhsNumber '= ""
	{
		set tsc = ..ConsentResource(nhsNumber)
	} 

	elseif LocalCode '= ""
	{
		set tsc = ..ConsentResource(LocalCode)
	} 
	
	
	Quit tsc
}

// Consent resource

Method ConsentResource(pIdentifier As %String) As %Status
{
	set tsc=$$$OK
	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "Consent"
	set resource.status = "Active"
	set resource.scope = "Patient-Privacy"
	set resource.patient = pIdentifier

	set policy = ##class(%DynamicArray).%New()
	set policyContent = ##class(%DynamicObject).%New()
	set policyContent.uri = "https://www.northerncarealliance.nhs.uk/fhir-profiles/smsconsentpolicy"
	do policy.%Push(policyContent)

	set resource.policy = policy

	$$$TRACE("ConsentResource= "_resource.%ToJSON())

	Quit tsc
}

// GPPractitionerRole resource

Method GPPractitionerRoleResource() As %Status
{
	set tsc = $$$OK

	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "PractitionerRole"

	set specialty = ##class(%DynamicObject).%New()
	set specialtyArray = ##class(%DynamicArray).%New()

	set tsc = ..CodebaleConcept("http://snomed.info/sct", "394814009", "General practice", .class, .specialtyCoding)

	do specialtyArray.%Push(specialtyCoding)
	set specialty.coding = specialtyArray

	set resource.specialty = specialty

	set practitionerArray = ##class(%DynamicArray).%New()
	set practitioner = ##class(%DynamicObject).%New()
	set practitioner.reference = "Practitioner/practitioner1"
	do practitionerArray.%Push(practitioner)

	set resource.practitioner = practitionerArray

	set organizationArray = ##class(%DynamicArray).%New()
	set organization = ##class(%DynamicObject).%New()
	set organization.reference = "Organization/Organization1"
	do organizationArray.%Push(organization)

	set resource.organization = organizationArray

	$$$TRACE("GPPractitionerRoleResource= "_resource.%ToJSON())

	Quit tsc
}

// PractitionerRole

Method PractitionerRoleResource() As %Status
{
	set tsc = $$$OK

	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "PractitionerRole"

	set specialty = ##class(%DynamicObject).%New()
	set specialtyArray = ##class(%DynamicArray).%New()
	set specialtyCoding = ##class(%DynamicObject).%New()

	set tsc = ..CodebaleConcept("LocalSpecialty-RW6_OR_LocalSpecialty-RM3", "######", "######", .class, .specialtyCoding)
	do specialtyArray.%Push(specialtyCoding)

	set tsc = ..CodebaleConcept("https://www.datadictionary.nhs.uk/attributes/main_specialty_code.html", "######", "######", .class, .specialtyCoding)
	do specialtyArray.%Push(specialtyCoding)

	set tsc = ..CodebaleConcept("https://www.datadictionary.nhs.uk/supporting_information/main_specialty_and_treatment_function_codes_table.html", "######", "######", .class, .specialtyCoding)
	do specialtyArray.%Push(specialtyCoding)

	set specialty.coding = specialtyArray

	set resource.specialty = specialty

	set practitionerArray = ##class(%DynamicArray).%New()
	set practitioner = ##class(%DynamicObject).%New()
	set practitioner.reference = "Practitioner/practitioner1"
	do practitionerArray.%Push(practitioner)

	set resource.practitioner = practitionerArray

	$$$TRACE("PractitionerRoleResource= "_resource.%ToJSON())

	Quit tsc
}

// Practitioner Resource

Method PractitionerResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK

	set PASLocal = pArr.GetAt("PASLocal")
	set NationalCode = pArr.GetAt("NationalCode")
	set ADLocal = pArr.GetAt("ADLocal")

	set GPFamilyName=pArr.GetAt("GPFamilyName")
	set GPGivenName=pArr.GetAt("GPGivenName")
	set GPPrefix=pArr.GetAt("GPPrefix")

	// Create a new resource
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the resource
	set resource.resourceType = "Practitioner"

	// PAS Local
	set identifierArray = ##class(%DynamicArray).%New()
	if PASLocal '= ""
	{
		set PASLocalContent = ##class(%DynamicObject).%New()
		Set PASLocalAssigner = ##class(%DynamicArray).%New()
		Set PASLocalAssignerContent = ##class(%DynamicObject).%New()
		set PASLocalContent.system = "https://www.northerncarealliance.nhs.uk/PAS-LOCAL"
		set PASLocalContent.value = PASLocal
		set PASLocalAssignerContent.reference = "Organization/RW6orRM3"
		do PASLocalAssigner.%Push(PASLocalAssignerContent)
		set PASLocalContent.assigner = PASLocalAssigner

		do identifierArray.%Push(PASLocalContent)
	}

	// National Code
	if NationalCode '= ""
	{
		set NationalCodeContent = ##class(%DynamicObject).%New()
		Set NationalCodeAssigner = ##class(%DynamicObject).%New()
		set NationalCodeContent.system = "https://fhir.hl7.org.uk/Id/gmc-number"
		set NationalCodeContent.value = NationalCode
		do identifierArray.%Push(NationalCodeContent)
	}

	/*
	if ADLocal '= ""
	{
		set ADLocalContent = ##class(%DynamicObject).%New()
		Set ADLocalAssigner = ##class(%DynamicObject).%New()
		set ADLocalContent.system = "https://www.northerncarealliance.nhs.uk/PAS-LOCAL"
		set ADLocalContent.value = ADLocal //need to be looked up??
		set ADLocalAssigner.identifier = "RW6orRM3" //need to be looked up??
		set ADLocalContent.assigner = ADLocalAssigner

		do identifierArray.%Push(ADLocalContent)
	}
	*/

	set resource.identifier = identifierArray

	// GP Name
	set GPnameArray = ##class(%DynamicArray).%New()
	set GPnameContent = ##class(%DynamicObject).%New()
	Set GPnameAssigner = ##class(%DynamicObject).%New()
	set GPnameContent.use = "official"
	set GPnameContent.family = GPFamilyName
	set GPnameContent.given = GPGivenName
	set GPnameContent.prefix = GPPrefix
	do GPnameArray.%Push(GPnameContent)

	set resource.name = GPnameArray
	$$$TRACE("PractitionerResource= "_resource.%ToJSON())

	Quit tsc
}

// Organization resource

Method OrganizationResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK
	set OdsCode = pArr.GetAt("odsOrganisationCode")

	// Create a new resource
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the resource
	set resource.resourceType = "Organization"

	// PAS Local
	set identifierArray = ##class(%DynamicArray).%New()
	if OdsCode '= ""
	{
		set OdsCodeContent = ##class(%DynamicObject).%New()
		Set OdsCodeIdentifierContent = ##class(%DynamicObject).%New()
		set OdsCodeContent.system = "https://www.northerncarealliance.nhs.uk/ODS-LOCAL"
		set OdsCodeContent.use = "official"
		set OdsCodeContent.value = OdsCode

		do identifierArray.%Push(OdsCodeContent)
	}

	set resource.identifier = identifierArray
	set resource.name = pArr.GetAt("OrganisationName")

	$$$TRACE("Organization= "_resource.%ToJSON())

	Quit tsc
}

// Location resource

Method LocationResource() As %Status
{
	set tsc = $$$OK

	// Create a new resource
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the resource
	set resource.resourceType = "Location"

	// PAS Local
	set identifierArray = ##class(%DynamicArray).%New()

	set LocationCodeContent1 = ##class(%DynamicObject).%New()
	set LocationCodeContent1.system = "https://fhir.nhs.uk/Id/ods-site-code"
	set LocationCodeContent1.value = "########"
	do identifierArray.%Push(LocationCodeContent1)

	Set LocationCodeAssigner = ##class(%DynamicArray).%New()
	set LocationCodeContent2 = ##class(%DynamicObject).%New()
	set LocationCodeContent2.system = "https://fhir.nhs.uk/Id/ods-site-code"
	set LocationCodeContent2.value = "########"

	set LocationCodeAssignerArray = ##class(%DynamicArray).%New()
	set LocationCodeAssigner = ##class(%DynamicObject).%New()
	set LocationCodeAssigner.reference = "Organization/RW6"
	do LocationCodeAssignerArray.%Push(LocationCodeAssigner)
	set LocationCodeContent2.assigner = LocationCodeAssignerArray
	do identifierArray.%Push(LocationCodeContent2)

	set resource.identifier = identifierArray

	// PhysicalType
	set tsc = ..CodebaleConcept("https://terminology.hl7.org/4.0.0/CodeSystem-location-physical-type.html", "######", "", .physicalType, .specialtyCoding)
	set resource.physicalType = physicalType

	// Name
	set resource.name = "########"

	$$$TRACE("Location= "_resource.%ToJSON())

	Quit tsc
}

// EpisodeOfCare resource

Method EpisodeOfCareResource() As %Status
{
	set tsc = $$$OK

	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "EpisodeOfCare"

	set identifier = ##class(%DynamicObject).%New()
	set identifierArray = ##class(%DynamicArray).%New()
	set identifierCoding = ##class(%DynamicObject).%New()
	set identifierCoding.system = " LocalEpisodeId"
	set identifierCoding.value = "########"

	set identifierAssigner = ##class(%DynamicObject).%New()
	set identifierAssignerArray = ##class(%DynamicArray).%New()
	set identifierAssigner.reference = "Organization/RW6"
	do identifierAssignerArray.%Push(identifierAssigner)

	set identifierCoding.assigner = identifierAssignerArray
	do identifierArray.%Push(identifierCoding)
	set resource.identifier = identifierArray

	set resource.status = "active" ;TBD

	; TBD: EpisodeOfCare.type
	
	set PatientReference = ##class(%DynamicObject).%New()
	set PatientReference.reference = "Patient/0123456"
	set resource.patient = PatientReference

	set tsc = ..SetPeriod("2022-11-01", "2022-11-10", .period)
	set resource.period = period

	$$$TRACE("EpisodeOfCareResource= "_resource.%ToJSON())

	Quit tsc
}

// EpisodeOfCare resource

Method EncounterResource() As %Status
{
	set tsc = $$$OK

	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "Encounter"

	// identifier
	set identifier = ##class(%DynamicObject).%New()
	set identifierArray = ##class(%DynamicArray).%New()
	set identifierCoding = ##class(%DynamicObject).%New()
	set identifierCoding.system = "http://example.com"
	set identifierCoding.value = "########"

	set identifierAssigner = ##class(%DynamicObject).%New()
	set identifierAssignerArray = ##class(%DynamicArray).%New()
	set identifierAssigner.reference = "Organization/RW6"
	do identifierAssignerArray.%Push(identifierAssigner)

	set identifierCoding.assigner = identifierAssignerArray
	do identifierArray.%Push(identifierCoding)
	set resource.identifier = identifierArray

	//status
	set resource.status = "finished"

	// Status History
	set stHist = ##class(%DynamicArray).%New()
	set stHistperiod = ##class(%DynamicObject).%New()

	set stHistperiod.status = "cancelled"

	set tsc = ..SetPeriod("2022-11-01", "2022-11-10", .period)
	set stHistperiod.period = period

	do stHist.%Push(stHistperiod)
	set resource.statusHistory = stHist

	// Class
	set tsc = ..CodebaleConcept("https://simplifier.net/packages/hl7.fhir.r4.core/4.0.1/files/80998/~overview", "AMB", "ambulatory", .pCodeConcept, .class)
	set resource.class = class

	// ServiceType
	set tsc = ..CodebaleConcept("http://snomed.info/sct", "736622005", "Aboriginal health service", .ServiceType, .Dynobject)
	set resource.serviceType = ServiceType

	// Priority
	set tsc = ..CodebaleConcept("http://terminology.hl7.org/CodeSystem/v3-ActPriority", "A", "ASAP", .Priority, .Dynobject)
	set resource.priority = Priority

	// Subject
	set Subject = ##class(%DynamicObject).%New()
	set Subject.reference = "patient/0123456"
	set resource.subject = Subject

	// EpisodeOfCare
	set EpisodeOfCare = ##class(%DynamicObject).%New()
	set EpisodeOfCare.reference = "episodeOfCare/0123456"
	set resource.episodeOfCare = EpisodeOfCare

	// BasedOn
	set BasedOn = ##class(%DynamicObject).%New()
	set BasedOn.reference = "serviceRequest/0123456"
	set resource.basedOn = BasedOn

	// Participant
	set participantArray = ##class(%DynamicArray).%New()
	set participantTypeArray = ##class(%DynamicArray).%New()
	set participantType = ##class(%DynamicObject).%New()

	set tsc = ..CodebaleConcept("http://terminology.hl7.org/CodeSystem/v3-ParticipationType", "ATND", "attender", .partType, .Dynobject)
	do participantTypeArray.%Push(partType)
	set participantType.type = participantTypeArray
	do participantArray.%Push(participantType)

	set resource.participant = participantArray

	// Period
	set tsc = ..SetPeriod("2022-11-01", "2022-11-10", .period)
	set resource.period = period

	// Location
	set Location = ##class(%DynamicObject).%New()
	set Location.reference = "Location/0123456"
	set resource.location = Location

	$$$TRACE("EncounterResource= "_resource.%ToJSON())

	Quit tsc
}

Method ServiceRequestResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK

	set resource = ##class(%DynamicObject).%New()
	set resource.resourceType = "Encounter"

	// identifier
	set identifier = ##class(%DynamicObject).%New()
	set identifierArray = ##class(%DynamicArray).%New()
	set identifierCoding = ##class(%DynamicObject).%New()
	set identifierCoding.value = "########"

	set identifierAssigner = ##class(%DynamicObject).%New()
	set identifierAssignerArray = ##class(%DynamicArray).%New()
	set identifierAssigner.reference = "Organization/RW6"
	do identifierAssignerArray.%Push(identifierAssigner)

	set identifierCoding.assigner = identifierAssignerArray
	do identifierArray.%Push(identifierCoding)
	set resource.identifier = identifierArray

	//status
	set resource.status = pArr.GetAt("SRstatus")
	
	// Priority
	set tsc = ..CodebaleConcept("http://terminology.hl7.org/CodeSystem/v3-ActPriority", "A", "ASAP", .Priority, .Dynobject)
	set resource.priority = Priority

	//Category
	set category = ##class(%DynamicArray).%New()
	set category.text = pArr.GetAt("SRcategoryText")
	set resource.category = category

	// Subject
	set Subject = ##class(%DynamicObject).%New()
	set Subject.reference = "Patient/0123456"
	set resource.subject = Subject

	// Encounter
	set Encounter = ##class(%DynamicObject).%New()
	set Encounter.reference = "Encounter/0123456"
	set resource.encounter = Encounter

	// LocationReference
	set LocationReference = ##class(%DynamicObject).%New()
	set LocationReference.reference = "Location/0123456"
	set resource.locationReference = LocationReference

	$$$TRACE("ServiceRequestResource= "_resource.%ToJSON())

	quit tsc
}

Method CodebaleConcept(pSystem As %String, pCode As %String, pDisplay As %String, Output pCodeConcept As %DynamicObject, Output pDynObject As %DynamicObject)
{
	set tsc = $$$OK

	set pCodeConcept = ##class(%DynamicObject).%New()
	set pDynObject = ##class(%DynamicObject).%New()
	set DynArray = ##class(%DynamicArray).%New()
	set pDynObject.system = pSystem
	set pDynObject.code = pCode
	set pDynObject.display = pDisplay
	do DynArray.%Push(pDynObject)

	set pCodeConcept.coding = DynArray

	quit tsc

    #; listpart is valid
}

Method SetPeriod(start As %String, end As %String, Output pDynObject As %DynamicObject)
{
	set tsc=$$$OK
	set pDynObject = ##class(%DynamicObject).%New()
	set pDynObject.start = start
	set pDynObject.end = end

	quit tsc
}

Method OnResponse() As %Status
{
	$$$TRACE("Trace_OnResponse")
	q $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
