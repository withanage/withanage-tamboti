xquery version "1.0";

import module namespace config = "http://exist-db.org/mods/config" at "../config.xqm";
import module namespace request = "http://exist-db.org/xquery/request";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

declare namespace xf = "http://www.w3.org/2002/xforms";
declare option exist:serialize "method=xml media-type=text/xml indent=yes";

(: codes-for-tab.xq
   This module will load all the code tables for a specific tab of a large multi-part form.
   Created for the MODS form.
   It calculates which tabs are needed by looking through the XForms body files
   in the edit/body collection of the mods editor.
   
   Input parameter: the tab ID
   Output: a list of all the code tables used by the tab in XML
   
   Author: Dan McCreary
   Date: Aug. 2010
   
   :)

(:~
: Gets the most recent modified time for a number of resources in the same collection
:
: @param collection-path The collection of the resources
: @param resources-name The filenames of the resources in the $collection-path to examine
:
: @return The most recently modified date of all the resources
:)
declare function local:get-last-modified($collection-path as xs:string, $resource-names as xs:string+) as xs:dateTime {
    fn:max(
        for $resource-name in $resource-names return
            xmldb:last-modified($collection-path, $resource-name)
    )
};

(:~
: Creates an Etag for the codetables
:
: The Etag has the format {tab-id}[debug]{$last-modified}
:
: We use the last-modified date in the Etag to ensure that the Etag
: changes if one of the underlying code-tables is modified
:)
declare function local:create-etag($last-modified as xs:dateTime) as xs:string {
    fn:concat(
        request:get-parameter("tab-id","-1"),
        request:get-parameter("debug", ""),
        $last-modified
    )
};


let $tab-id := request:get-parameter('tab-id', '')
let $debug := xs:boolean(request:get-parameter('debug', 'false'))

(: TODO check for required tab-id parameter and make sure that the tab is a valid tab ID
let $check-tab := if ( string-length($tab-id) < 1 )
  then
        <error>
           <message>Tab ID is a required parameter.</message>
        </error>
else
:)

let $code-table-collection := concat($config:edit-app-root, '/code-tables/')
let $xforms-body-collection := concat($config:edit-app-root, '/body')
let $itemsets := collection($xforms-body-collection)/*[@tab-id=$tab-id]//xf:itemset
let $code-table-names :=
   for $itemset in $itemsets
      let $nodeset := string($itemset/@nodeset)
      let $after := substring-after($nodeset, "code-table-name='")
      let $code-table-name := substring-before($after, "']/items/item")
      order by $code-table-name
      return $code-table-name
let $distinct-code-table-names := (distinct-values($code-table-names), 'hint-code')

(: generate etag :)
let $last-modified := local:get-last-modified($code-table-collection,
    for $distinct-code-table-name in $distinct-code-table-names return
        concat($distinct-code-table-name, 's.xml')
)
let $etag := local:create-etag($last-modified) return
(
    (: set some caching http headers :)
    response:set-header("Etag", $etag),
    response:set-header("Last-Modified", $last-modified),

    (: have we previously made the same request for the same un-modified code-tables? :)
    if(request:get-header("If-None-Match") eq $etag)then
    (
        (: yes, so send not modified :)
        response:set-status-code(304)
    ) else (
        (: no, so process the request:)
        let $itemset-count := count($itemsets)
        let $count-distinct := count($distinct-code-table-names) return
        <code-tables>
        {
            if($debug) then
                <debug>
                    <code-table-collection>{$code-table-collection}</code-table-collection>
                    <xforms-body-collection>{$xforms-body-collection}</xforms-body-collection>
                    <tab-id>{$tab-id}</tab-id>
                    <itemset-count>{$itemset-count}</itemset-count>
                    <code-table-name-count>{$count-distinct}</code-table-name-count>
                    <distinct-code-table-names>{$distinct-code-table-names}</distinct-code-table-names>
                </debug>
            else(),
           
            for $code-table-name in $distinct-code-table-names
              let $log := util:log("DEBUG", ("##$code-table-name): ", $code-table-name))
              let $file-path := concat($code-table-collection, $code-table-name, 's.xml')
              let $code-table := doc($file-path) return
                 (:NB: An empty code-table is created; this has an empty xml:id which has to be filled with an NCName.:)
                 <code-table xml:id="{if ($code-table-name) then $code-table-name else 'xxx'}">
                    <code-table-name>{$code-table-name}</code-table-name>
                    <items>
                    {
                        for $item in $code-table//item return
                            $item
                    }
                    </items>
                 </code-table>
        }
        </code-tables>
    )
)
(:
   Before Etag support was implemented, fastest response was 35ms
   After ETag support was implemented, fastest response is 39ms, however when Etag is used, response is just 14ms :-)
:)