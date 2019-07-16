--==================================================================== COMMANDS
{-
    elm repl
    elm init
    elm reactor
    elm install NAME/PACKAGE
    elm make --output=FILENAME.js FILENAME.elm
-}
--==================================================================== PACKAGE DEPENDENCIES
{-
    elm/core
    elm/html
    elm/browser
    elm/file
    elm/json

    Gizra/elm-keyboard-event
    SwiftsNamesake/proper-keyboard
    mpizenberg/elm-pointer-events
    periodic/elm-csv
-}
--==================================================================== IMPORTS

--Standard
import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Html.Lazy exposing (lazy)
import Browser exposing (Document, document)
import Browser.Dom exposing (..)
import File exposing (File)
import File.Select exposing (file)
import File.Download exposing (string)
import Task exposing (perform, attempt)
import Maybe exposing (withDefault)
import List exposing (length, repeat, map)

--Special
import Csv exposing (Csv, parse)
import Json.Decode exposing (map, succeed)
import Keyboard.Event exposing (KeyboardEvent, decodeKeyboardEvent)
import Keyboard.Key exposing (Key(..))

--==================================================================== MAIN

main : Program () Model Msg
main =
  Browser.document
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

--==================================================================== MODEL

type alias Model = {sidePanelExpanded : Bool, records : List Record, oldRecords : List OldRecord, filename : String}
type alias Record = {oldLotNo : String, lotNo : String, vendor : String, description : String, reserve : String}
type alias OldRecord = {lotNo : String, vendor : String, description : String, reserve : String}

type Msg
  = NoOp
  | HandleErrorEvent String
  | HandleKeyboardEvent KeyboardEventType KeyboardEvent

  | ToggleSidePanel

  | CsvRequested Bool
  | CsvSelected Bool File
  | CsvLoaded Bool String String
  | CsvExported

  | ClearAll

  | FilenameEdited String

  | TableScrolled
  | ScrollInfo Viewport

type KeyboardEventType = KeyboardEventType

--==================================================================== INIT

init : () -> (Model, Cmd Msg)
init _ = (Model False [] [] "", Cmd.none)

--==================================================================== VIEW

view : Model -> Document Msg
view = lazy vieww >> List.singleton >> Document "Otter"

vieww : Model -> Html Msg
vieww model =
  div [ class "ui two column grid remove-gutters" ]
    [ div [ class "row" ]
        [ div [ class <| (if model.sidePanelExpanded then "twelve" else "fifteen") ++ " wide column" ]
            [ div [ class "table-sticky", onScroll TableScrolled, id "table-container" ]
                [ table [ class "ui single line fixed unstackable celled striped compact table header-color row-height-fix" ]
                    [ col [ attribute "width" "100px" ] []
                    , col [ attribute "width" "100px" ] []
                    , col [ attribute "width" "100px" ] []
                    , col [ attribute "width" "300px" ] []
                    , col [ attribute "width" "100px" ] []
                    , thead []
                        [ tr []
                            [ th [] [ text "Old Lot No." ]
                            , th [] [ text "Lot No." ]
                            , th [] [ text "Vendor" ]
                            , th [] [ text "Item Description" ]
                            , th [] [ text "Reserve" ]
                            ]
                        ]
                    , tbody [ class "first-row-height-fix" ]
                        (List.map recordToRow model.records
                    ++  [ tr [ class "positive" ]
                            [ td [] []
                            , td [] []
                            , td [] []
                            , td [] []
                            , td [] []
                            ]
                        ])
                    ]
                ]
            ]
        , div [ class <| (if model.sidePanelExpanded then "four" else "one") ++ " wide column" ]
            [ div [ class "ui segments" ]
                [ if model.sidePanelExpanded then
                  div [ class "ui segment" ]
                    [ h1 [ class "ui header horizontal-center" ] [ text "Otter" ]
                    , div [ class "ui form" ]
                        [ div [ class "field" ]
                            [ div [ class "ui right labeled input" ]
                                [ input [ placeholder "Filename", onInput FilenameEdited, type_ "text", value model.filename ] []
                                , div [ class "ui label" ] [ text ".csv" ]
                                ]
                            ]
                        , div [ class "field" ]
                            [ div [ class "ui buttons" ]
                                [ button [ class "ui button blue", onClick ClearAll ]
                                    [ i [ class "asterisk icon" ] []
                                    , text "New"
                                    ]
                                , button [ class "ui button yellow", onClick <| CsvRequested True ]
                                    [ i [ class "certificate icon" ] []
                                    , text "Add Suggestions"
                                    ]
                                , button [ class "ui button green", onClick CsvExported ]
                                    [ i [ class "file export icon" ] []
                                    , text "Save"
                                    ]
                                , button [ class "ui button purple", onClick <| CsvRequested False ]
                                    [ i [ class "file import icon" ] []
                                    , text "Import"
                                    ]
                                ]
                            ]
                        ]
                    ]
                  else
                  div [] []
                , div [ class "ui segment horizontal-center" ]
                    [ button [ class "huge circular blue ui icon button", onClick ToggleSidePanel ]
                        [ i [ class <| "angle " ++ (if model.sidePanelExpanded then "right" else "left") ++ " icon" ] []
                        ]
                    ]
                ]
            ]
        ]
    ]

recordToRow : Record -> Html Msg
recordToRow {oldLotNo, lotNo, vendor, description, reserve} =
  tr []
    [ td [] [ text oldLotNo ]
    , td [] [ text lotNo ]
    , td [] [ text vendor ]
    , td [] [ text description ]
    , td [] [ text reserve ]
    ]

--e.g. onKeyboardEvent MovingCursor "keydown"
onKeyboardEvent : KeyboardEventType -> String -> Attribute Msg
onKeyboardEvent eventType eventName =
  on eventName <| map (HandleKeyboardEvent eventType) decodeKeyboardEvent

onScroll : msg -> Attribute msg
onScroll msg = on "scroll" (succeed msg)

--==================================================================== UPDATE

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NoOp -> (model, Cmd.none)
    HandleErrorEvent message -> (print message model, Cmd.none)
    HandleKeyboardEvent eventType event -> (model, Cmd.none)

    ToggleSidePanel -> let newExpanded = not model.sidePanelExpanded in ({model | sidePanelExpanded = newExpanded}, Cmd.none)

    CsvRequested suggestion -> (model, file [ csv_mime ] <| CsvSelected suggestion)
    CsvSelected suggestion file -> (model, Task.perform (CsvLoaded suggestion <| File.name file) (File.toString file))
    CsvLoaded suggestion fileName fileContent ->
      ( case parse fileContent of
          Err _ -> model
          Ok csv -> if suggestion
                    then {model | oldRecords = List.map listToOldRecord csv.records}
                    else {model | records = model.records ++ List.map listToRecord csv.records}
      , Cmd.none
      )
    CsvExported ->
      ( model
      , string ((if model.filename == "" then "export" else model.filename) ++ ".csv") csv_mime (recordsToCsv model.records)
      )

    ClearAll -> ({model | records = []}, Cmd.none)

    FilenameEdited newText -> ({ model | filename = newText}, Cmd.none)

    TableScrolled -> (model, attempt (handleError ScrollInfo) <| getViewportOf "table-container")
    ScrollInfo viewport -> (print viewport.viewport.y model, Cmd.none)

listToOldRecord : List String -> OldRecord
listToOldRecord list =
  case pad 4 "" list of
    (a :: b :: c :: d :: xs) -> OldRecord a b c d
    _ -> OldRecord "ERROR" "ERROR" "ERROR" "ERROR"

listToRecord : List String -> Record
listToRecord list =
  case pad 4 "" list of
    (a :: b :: c :: d :: xs) -> Record "" a b c d
    _ -> Record "ERROR" "ERROR" "ERROR" "ERROR" "ERROR"

--e.g. Task.attempt handleError
handleError : (a -> Msg) -> Result Error a -> Msg
handleError onSuccess result =
  case result of
    Err (NotFound message) -> HandleErrorEvent message
    Ok value -> onSuccess value

recordsToCsv : List Record -> String
recordsToCsv records =
  let recordToCsv {oldLotNo, lotNo, vendor, description, reserve} = String.join "," [lotNo, vendor, description, reserve]
   in String.join windows_newline <| List.map recordToCsv records

--==================================================================== SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

--==================================================================== PRELUDE

silence : Result e a -> Maybe a
silence result =
  case result of
    Ok value -> Just value
    Err _ -> Nothing

flip : (a -> b -> c) -> b -> a -> c
flip f a b = f b a

curry : (a -> b -> c) -> (a, b) -> c
curry f (a, b) = f a b

uncurry : ((a, b) -> c) -> a -> b -> c
uncurry f a b = f (a, b)

zipWith : (a -> b -> c) -> List a -> List b -> List c
zipWith f a b =
  case (a, b) of
    ([], _) -> []
    (_, []) -> []
    (x :: xs, y :: ys) -> f x y :: zipWith f xs ys

updateAt : Int -> (a -> a) -> List a -> List a
updateAt n f lst =
  case (n, lst) of
    (_, []) -> []
    (0, (x :: xs)) -> f x :: xs
    (nn, (x :: xs)) -> x :: updateAt (nn - 1) f xs

pad : Int -> a -> List a -> List a
pad n def list =
  list ++ repeat (Basics.max (n - length list) 0) def

--==================================================================== DEBUGGING

print : a -> b -> b
print a b = always b <| Debug.log "" (Debug.toString a)

printt : a -> a
printt a = print a a

--==================================================================== CONSTS

windows_newline : String
windows_newline = "\r\n"

csv_mime : String
csv_mime = "text/csv"
