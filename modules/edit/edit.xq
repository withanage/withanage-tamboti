xquery version "1.0";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace sm = "http://exist-db.org/xquery/securitymanager"; (: TODO move code into security module :)
import module namespace util = "http://exist-db.org/xquery/util";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

import module namespace style = "http://exist-db.org/mods-style" at "style.xqm";
import module namespace mods = "http://www.loc.gov/mods/v3" at "tabs.xqm";
import module namespace config = "http://exist-db.org/mods/config" at "../config.xqm";
import module namespace security = "http://exist-db.org/mods/security" at "../search/security.xqm"; (: TODO move security module up one level :)
import module namespace uu="http://exist-db.org/mods/uri-util" at "../search/uri-util.xqm";

declare namespace xf="http://www.w3.org/2002/xforms";
declare namespace xforms="http://www.w3.org/2002/xforms";
declare namespace ev="http://www.w3.org/2001/xml-events";
declare namespace xlink="http://www.w3.org/1999/xlink";
declare namespace e="http://www.asia-europe.uni-heidelberg.de/";
declare namespace mads="http://www.loc.gov/mads/";

declare function local:get-target-collection($target-collection as xs:string) as xs:string {
    let $target-collection := uu:escape-collection-path(request:get-parameter("collection", ""))
    return $target-collection};

declare function local:create-new-record($id as xs:string, $type-request as xs:string, $target-collection as xs:string) as empty() {
       (: Copy the template into data and store it with the ID as file name. :)
       let $log := util:log("DEBUG", ("##$id-edit1): ", $id))
       let $log := util:log("DEBUG", ("##$target-collection1): ", $target-collection))
       let $template-doc := doc(concat($config:edit-app-root, '/instances/', $type-request, '.xml')),
       (: Store it in the right location :)
       (:$log := util:log("DEBUG", ("##$type-request): ", $type-request)),:)
       $stored := xmldb:store($config:mods-temp-collection, concat($id, '.xml'), $template-doc),
       
       (: TEMP whilst eXist-db permissions remain rwu, once they are rwx - this can be changed to rw :)
       $null := sm:chmod(xs:anyURI($stored), "rwu------"),
       
       (: Get the remaining parameters. :)
       (: Parameter 'host' is used when related records are created. :)
       $host := request:get-parameter('host', ""),
       $languageOfResource := request:get-parameter("languageOfResource", ""),
       $scriptOfResource := request:get-parameter("scriptOfResource", ""),
       $transliterationOfResource := request:get-parameter("transliterationOfResource", ""),
       $languageOfCataloging := request:get-parameter("languageOfCataloging", ""),
       $scriptOfCataloging := request:get-parameter("scriptOfCataloging", ""),
       (: Determine if script is Latin or not. :)
       (:$scriptTypeOfResource := doc(concat($config:edit-app-root, "/code-tables/language-3-type-codes.xml"))/code-table/items/item[value = $languageOfResource]/data(scriptClassifier),:)
       (:$scriptTypeOfCataloging := doc(concat($config:edit-app-root, "/code-tables/language-3-type-codes.xml"))/code-table/items/item[value = $languageOfCataloging]/data(scriptClassifier),:)
       
       $doc := doc($stored)
         
       (: Note that we can not use "update replace" if we want to keep the default namespace. :)
       return (
       
          (: Update record with ID attribute. :)
          update value $doc/mods:mods/@ID with $id,
          update value $doc/mads:mads/@ID with $id
          ,
          (: Save language and script of resource. :)
          let $language-insert:=
              <mods:language>
                  <mods:languageTerm authority="iso639-2b" type="code">
                      {$languageOfResource}
                  </mods:languageTerm>
                  <mods:scriptTerm authority="iso15924" type="code">
                      {$scriptOfResource}
                  </mods:scriptTerm>
              </mods:language>
          return
          update insert $language-insert into $doc/mods:mods
          ,
          (: Save creation date and language and script of cataloguing :)
          let $recordInfo-insert:=
              <mods:recordInfo lang="eng" script="latn">
                  <mods:recordContentSource authority="marcorg">DE-16-158</mods:recordContentSource>
                  <mods:recordCreationDate encoding="w3cdtf">
                      {current-date()}
                  </mods:recordCreationDate>
                  <mods:recordChangeDate encoding="w3cdtf"/>
                  <mods:languageOfCataloging>
                      <mods:languageTerm authority="iso639-2b" type="code">
                          {$languageOfCataloging}
                      </mods:languageTerm>
                      <mods:scriptTerm authority="iso15924" type="code">
                          {$scriptOfCataloging}
                  </mods:scriptTerm>
                  </mods:languageOfCataloging>
              </mods:recordInfo>            
          return
          update insert $recordInfo-insert into $doc/mods:mods
          ,
          (: Save name of user collection, name of template used, script type and transliteration scheme used into mods:extension. :)
          (: NB: it should not be necessary to save $target-collection in the document, to be picked up in save.xq and then removed! :)  
          update insert
              <extension xmlns="http://www.loc.gov/mods/v3" xmlns:e="http://www.asia-europe.uni-heidelberg.de/">
                  <e:collection>{$target-collection}</e:collection>
                  <e:template>{$type-request}</e:template>
                  <e:transliterationOfResource>{$transliterationOfResource}</e:transliterationOfResource>                    
              </extension>
          into $doc/mods:mods
          ,
          if ($host)
          then
            (
                update value doc($stored)/mods:mods/mods:relatedItem/@xlink:href with concat('#', $host),
                update value doc($stored)/mods:mods/mods:relatedItem/@type with "host"
            )
          else ()
      )
};

declare function local:create-xf-model($id as xs:string, $tab-id as xs:string, $instance-id as xs:string) as element(xf:model) {

    let $instance-src := concat('get-instance.xq?tab-id=', $tab-id, '&amp;id=', $id, '&amp;data=', $config:mods-temp-collection)
    let $log := util:log("DEBUG", ("##-$tab-id): ", $tab-id))
    let $log := util:log("DEBUG", ("##$id-edit2): ", $id))
    return

        <xf:model>
           <xf:instance xmlns="http://www.loc.gov/mods/v3" src="{$instance-src}" id="save-data"/>
           
           (: The instance insert-templates contain an almost full embodiment of the MODS schema, version 3.4; 
           the full 3.4 schema is reflected in full-3.4-instance.xml. :)
           <xf:instance xmlns="http://www.loc.gov/mods/v3" src="instances/insert-templates.xml" id='insert-templates' readonly="true"/>
           
           (: A selection of elements and attributes from the MODS schema used for default records. :)
           <xf:instance xmlns="http://www.loc.gov/mods/v3" src="instances/new-instance.xml" id='new-instance' readonly="true"/>
           
           (: A selection of elements and attributes from the MADS schema used for default records. :)
           <xf:instance xmlns="http://www.loc.gov/mads/" src="instances/mads.xml" id='mads' readonly="true"/>
    
           (: Elements and attributes for insertion into the compact forms. :)
           <xf:instance xmlns="http://www.loc.gov/mods/v3" src="instances/compact-template.xml" id='compact-template' readonly="true"/> 
           
           <xf:instance id="code-tables" src="codes-for-tab.xq?tab-id={$instance-id}" readonly="true"/>
           
           <!-- a title should ideally speaking be required, but having this bind will prevent a tab from being saved when clicking on another tab, if the user has not input a title.--> 
           <!--
           <xf:bind nodeset="instance('save-data')/mods:titleInfo/mods:title" required="true()"/>       
           -->
           
           <xf:submission id="save-submission" method="post"
              ref="instance('save-data')"
              action="save.xq?collection={$config:mods-temp-collection}&amp;action=save" replace="instance"
              instance="save-results">
           </xf:submission>
           
           <xf:submission id="save-and-close-submission" method="post"
              ref="instance('save-data')"
              action="save.xq?collection={$config:mods-temp-collection}&amp;action=close" replace="instance"
              instance="save-results">
           </xf:submission>
           
           <xf:submission id="cancel-submission" method="post"
              ref="instance('save-data')"
              action="save.xq?collection={$config:mods-temp-collection}&amp;action=cancel" replace="instance"
              instance="save-results">
           </xf:submission>
        </xf:model>
};

declare function local:create-page-content($id as xs:string, $tab-id as xs:string, $type-request as xs:string, $target-collection as xs:string, $instance-id as xs:string, $record-data as xs:string, $type-data as xs:string) as element(div) {
let $log := util:log("DEBUG", ("##$id-edit3): ", $id))
let $log := util:log("DEBUG", ("##$target-collection2): ", $target-collection))
    (: Get the part of the form that belongs to the tab called. :)
    let $form-body := collection(concat($config:edit-app-root, '/body'))/div[@tab-id = $instance-id],
    (: Get the relevant information to display on the top line, starting with "Editing record". :)
    $type-label := doc($type-data)/code-table/items/item[value = $type-request]/label,
    $type-hint := doc($type-data)/code-table/items/item[value = $type-request]/hint,
    (: Display the label attached to the tab to the user :)
    $tab-data := concat($config:edit-app-root, '/tab-data.xml'),
    $bottom-tab-label := doc($tab-data)/tabs/tab[tab-id=$tab-id]/*[local-name() = $type-request],
    $bottom-tab-label := 
    	if ($bottom-tab-label)
    	then $bottom-tab-label
    	else doc($tab-data)/tabs/tab[tab-id=$tab-id]/label    	
    return
        <div class="content">
            <span class="info-line">
            {
                if ($type-request)
                then (
                    'Editing record of type ', 
                    <strong>{$type-label}</strong>,
                    if ($type-hint) 
                    then
                        <span class="xforms-help">
                            <span onmouseover="show(this, 'hint', true)" onmouseout="show(this, 'hint', false)" class="xforms-hint-icon"/>
                            <div class="xforms-help-value">{$type-hint}</div>
                        </span>
                    else ()
                ) else 'Editing record'
                ,
                let $publication-title := concat(doc($record-data)/mods:mods/mods:titleInfo[string-length(@type) = 0][1]/mods:nonSort, ' ', doc($record-data)/mods:mods/mods:titleInfo[string-length(@type) = 0][1]/mods:title) return
                    if ($publication-title != ' ') 
                    then (' with the title ', <strong>{$publication-title}</strong>) 
                    else ()
                }, on the <strong>{$bottom-tab-label}</strong> tab, to be saved in <strong> {
                    let $target-collection-display := replace(replace($target-collection, '/db/resources/users/', ''), '/db/resources/commons/', '') 
                    return
                        if ($target-collection-display eq security:get-user-credential-from-session()[1])
                        then 'resources/Home'
                        else concat('resources/', $target-collection-display)
                }</strong>.
            </span>
            
            <!--Here values are passed to the URL.-->
            {mods:tabs($tab-id, $id, $target-collection)}
        
            <div class="save-buttons">    
                <xf:submit submission="save-submission">
                    <xf:label class="xforms-group-label-centered-general">Save</xf:label>
                </xf:submit>
             
                <xf:trigger>
                    <xf:label class="xforms-group-label-centered-general">Save and Close</xf:label>
                    <xf:action ev:event="DOMActivate">
                        <xf:send submission="save-and-close-submission"/>
                        <xf:load resource="../../modules/search/index.html?filter=ID&amp;value={$id}&amp;collection={replace($target-collection, '/db', '')}" show="replace"/>
                    </xf:action>
                </xf:trigger>
             
                <xf:trigger>
                    <xf:label class="xforms-group-label-centered-general">Cancel Editing</xf:label>
                    <xf:action ev:event="DOMActivate">
                        <xf:send submission="cancel-submission"/>
                        <xf:load resource="../../?reload=true" show="replace"/>
                    </xf:action>
                 </xf:trigger>
             
                <span class="xforms-hint">
                    <span onmouseover="show(this, 'hint', true)" onmouseout="show(this, 'hint', false)" class="xforms-hint-icon"/>
                    <div class="xforms-hint-value">
                        <p>Every time you click one of the tabs, your input is saved. For this reason, there is generally no need to click the &quot;Save&quot; button. </p>
                        <p>Be aware, however, that you are only logged in for a certain period of time and when your session times out, what you have input cannot be retrieved. 
                        You can keep your session alive by clicking any tab. When your session is about to expire, you are prompted to keep it alive.</p> 
                        <p>If you know that you may not be able to finish a record, it is best to click &quot;Save and Close&quot; and return to finish the record later.</p>
                        <p>When you click the &quot;Save and Close&quot; button, the record is saved inside the folder you marked before opening the editor or the folder from which you opened it for re-editing.</p>
                        <p>You can continue editing the record by finding it and clicking the &quot;Edit Record&quot; button inside the record&apos;s detail view.</p>
                        <p>If you wish to discard what you have input and return to the search function, click &quot;Cancel Editing&quot;.</p>
                    </div>
                </span>
            </div>
            
            <!-- Import the correct form body for the tab called. -->
            {$form-body}
            
            <div class="save-buttons">    
                <xf:submit submission="save-submission">
                    <xf:label class="xforms-group-label-centered-general">Save</xf:label>
                </xf:submit>
             
                <xf:trigger>
                    <xf:label class="xforms-group-label-centered-general">Save and Close</xf:label>
                    <xf:action ev:event="DOMActivate">
                        <xf:send submission="save-and-close-submission"/>
                        <xf:load resource="../../modules/search/index.html?filter=ID&amp;value={$id}&amp;collection={replace($target-collection, '/db', '')}" show="replace"/>
                    </xf:action>
                </xf:trigger>
             
                <xf:trigger>
                    <xf:label class="xforms-group-label-centered-general">Cancel Editing</xf:label>
                    <xf:action ev:event="DOMActivate">
                        <xf:send submission="cancel-submission"/>
                        <xf:load resource="../../?reload=true" show="replace"/>
                    </xf:action>
                 </xf:trigger>
             
                <span class="xforms-hint">
                    <span onmouseover="show(this, 'hint', true)" onmouseout="show(this, 'hint', false)" class="xforms-hint-icon"/>
                    <div class="xforms-hint-value">
                        <p>Every time you click one of the tabs, your input is saved. For this reason, there is generally no need to click the &quot;Save&quot; button. </p>
                        <p>Be aware, however, that you are only logged in for a certain period of time and when your session times out, what you have input cannot be retrieved. 
                        You can keep your session alive by clicking any tab. When your session is about to expire, you are prompted to keep it alive.</p> 
                        <p>If you know that you may not be able to finish a record, it is best to click &quot;Save and Close&quot; and return to finish the record later.</p>
                        <p>When you click the &quot;Save and Close&quot; button, the record is saved inside the folder you marked before opening the editor or the folder from which you opened it for re-editing.</p>
                        <p>You can continue editing the record by finding it and clicking the &quot;Edit Record&quot; button inside the record&apos;s detail view.</p>
                        <p>If you wish to discard what you have input and return to the search function, click &quot;Cancel Editing&quot;.</p>
                    </div>
                </span>
            </div>
        </div>
};

declare function local:get-instance-id($tab-id as xs:string, $type-request as xs:string) {
    if ($tab-id ne 'compact-b')
    then $tab-id
    else 
	    if ($type-request = ('article-in-periodical-latin', 'article-in-periodical-transliterated'))
	    then 'compact-b-periodical' 
	    else 
		    if ($type-request = ('contribution-to-edited-volume-latin', 'contribution-to-edited-volume-transliterated'))
		    then 'compact-b-anthology'
		    else
		    if ($type-request = ('monograph-latin', 'monograph-transliterated', 'edited-volume-latin', 'edited-volume-transliterated'))
		    then 'compact-b-series'
		    else 
			    if ($type-request = ('book-review-latin', 'book-review-transliterated'))
			    then 'compact-b-review'
			    else 
				    if ($type-request = 'suebs-tibetan')
				    then 'compact-b-suebs-tibetan'
				    else
				        if ($type-request = 'mads')
				        then 'mads'
				        else 'compact-b-xlink'
};

(: If a document type is specified, then we will need to use that instance as the template. :)
let $record-id := request:get-parameter('id', '')
let $record-data := concat($config:mods-temp-collection, "/", $record-id,'.xml')

(: If the record has been made with Tamoboti, it will have a template. 
If the record is being opened from the search interface, the template name has to be retrieved in order to serve the right subform. :)
(: NB: $stored-template has no value when a stored record is loaded for the first time. :)
let $stored-template := doc($record-data)/mods:mods/mods:extension/e:template
(: Get the type parameter which shows which record template has been chosen.:) 
let $type-request := request:get-parameter('type', $stored-template)
(: If there is no type parameter, use the stored template instead. :)
let $type-request := 
	if ($type-request)
	then $type-request
	else $stored-template

let $type-data := concat($config:edit-app-root, '/code-tables/document-type-codes.xml')

(: If type-sort is '1', it is a compact form and the Basic Input Forms should be shown; 
if type-sort is 3, it is a mads record and the MADS forms should be shown; 
otherwise it is an unspecified instance and Title Information should be shown. :)
let $type-sort := doc($type-data)/code-table/items/item[value = $type-request]/sort
let $log := util:log("DEBUG", ("##$type-sort): ", $type-sort))
(: Get the default tab-id. If no tab is specified, default to the compact-a tab in the case of a template to be used with Basic Input Forms;
otherwise default to Title Information. :)
let $default-tab-id :=
    if ($type-sort = 1 or not($type-request))
    then 'compact-a'
    else
        if ($type-sort = 3)
        then 'mads'
        else 'title'
        
let $tab-id := request:get-parameter('tab-id', $default-tab-id)

let $target-collection := uu:escape-collection-path(request:get-parameter("collection", ""))
let $log := util:log("DEBUG", ("##$target-collection3): ", $target-collection))
(: Get id parameter. Default to "new" if empty. :)
let $id-param := request:get-parameter('id', 'new')

(: Check to see if we have an id. :)
let $new-record := xs:boolean($id-param = '' or $id-param = 'new')

(: If we do not have an incoming ID or if the record is new, then create an ID with util:uuid(). :)
let $id :=
	if ($new-record)
    then concat("uuid-", util:uuid())
    else $id-param

(: If we are creating a new record, then we need to call get-instance.xq with new=true to tell it to get the entire template; 
if not, we copy the record from the target collection to temp. :)
let $create-new-from-template :=
	if ($new-record) 
	then local:create-new-record($id, $type-request, $target-collection)
	else 
   		if (not(doc-available(concat($config:mods-temp-collection, '/', $id, '.xml'))))
   		then xmldb:copy($target-collection, $config:mods-temp-collection, concat($id, '.xml'))
   		else ()

(: For a compact-b form, determine which subform to serve, based on the template. :)
let $instance-id := local:get-instance-id($tab-id, $type-request)

(: $style appears to be introduced in order to use the xf namespace in css. :)
let $style := <style type="text/css"><![CDATA[@namespace xf url(http://www.w3.org/2002/xforms);]]></style>
let $model := local:create-xf-model($id, $tab-id, $instance-id)
let $content := local:create-page-content($id, $tab-id, $type-request, $target-collection, $instance-id, $record-data, $type-data)
let $log := util:log("DEBUG", ("##$target-collection4): ", $target-collection))
return 
    style:assemble-form('', attribute {'mods:dummy'} {'dummy'}, $style, $model, $content, false())
    
