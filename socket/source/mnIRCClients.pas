unit mnIRCClients;
{$M+}
{$H+}
{$IFDEF FPC}
{$MODE delphi}
{$ELSE}
{$ENDIF}
{**
 *  This file is part of the "Mini Library"
 *  @license  modifiedLGPL (modified of http://www.gnu.org/licenses/lgpl.html)
 *            See the file COPYING.MLGPL, included in this distribution,
 *  @ported from SlyIRC the orignal author Steve Williams
 *  @author by Zaher Dirkey <zaher at parmaja dot com>


    https://en.wikipedia.org/wiki/List_of_Internet_Relay_Chat_commands
    https://stackoverflow.com/questions/12747781/irc-message-format-clarification

    //Yes we can read in thread and write in main thread
    https://stackoverflow.com/questions/7418093/use-one-socket-in-two-threads
 *}

interface

uses
  Classes, StrUtils,
  mnClasses,
  mnSockets, mnSocketStreams, mnClients, mnStreams, mnConnections, mnUtils, syncobjs;

const
  cTokenSeparator = ' ';    { Separates tokens, except for the following case. }

  //https://www.alien.net.au/irc/irc2numerics.html
  IRC_RPL_WELCOME = 001;
  IRC_RPL_WHOISUSER = 311;
  IRC_RPL_ENDOFWHO = 315;
  IRC_RPL_WHOISACCOUNT = 330;
  IRC_RPL_TOPIC = 332;
  IRC_RPL_TOPICWHOTIME = 333;
  IRC_RPL_NAMREPLY = 353;
  IRC_RPL_WHOSPCRPL = 354;
  IRC_RPL_ENDOFNAMES = 366;
  IRC_RPL_MOTDSTART = 375;
  IRC_RPL_INFO = 371;
  IRC_RPL_MOTD = 372;
  IRC_RPL_INFOSTART = 373;
  IRC_RPL_ENDOFINFO = 374;
  IRC_RPL_ENDOFMOTD = 376;

type

  { TIRCSocketStream }

  TIRCSocketStream = Class(TmnClientSocketStream)
  protected
  end;

  TmnIRCClient = class;

  TIRCMsgType = (mtNotice, mtSend, mtReceive);
  TIRCLogType = (lgMsg, lgSend, lgReceive);

  { TIRCCommand }

  TIRCCommand = class(TObject)
  private
    FRaw: String;
    //FCode: string;
    FName: string;

    FTime: string;
    FText: string;
    FSource: string;
    FTarget: string;
    FParams: TStringList;
  protected
    property Raw: String read FRaw;
    procedure Parse(vData: string); virtual; deprecated;
  public
    constructor Create;
    destructor Destroy; override;

    property Source: string read FSource;
    property Target: string read FTarget;

    property Name: string read FName;//Name or Code
    property Text: string read FText; //Rest body of msg after : also added as last param

    property Params: TStringList read FParams;
  end;

  { TIRCReceiver }

  TIRCReceiver = class(TObject)
  private
    FClient: TmnIRCClient;
  protected
    procedure DoReceive(vCommand: TIRCCommand); virtual; abstract;
    function Accept(S: string): Boolean; virtual;
    procedure Receive(vCommand: TIRCCommand); virtual;
    property Client: TmnIRCClient read FClient;
    procedure DoParse(vCommand: TIRCCommand; vData: string); virtual;
    procedure Parse(vCommand: TIRCCommand; vData: string);
  public
    Name: String;
    Code: Integer;
    constructor Create(AClient: TmnIRCClient); virtual;
  end;

  TIRCReceiverClass = class of TIRCReceiver;

  { TCustomIRCReceivers }

  //We should use base class TmnCommandClasses, TODO

  TCustomIRCReceivers = class(TmnNamedObjectList<TIRCReceiver>)
  private
    FClient: TmnIRCClient;
  public
    constructor Create(AClient: TmnIRCClient);
    destructor Destroy; override;
    function Add(vName: String; vCode: Integer; AClass: TIRCReceiverClass): Integer;
    procedure Receive(ACommand: TIRCCommand);
    property Client: TmnIRCClient read FClient;
  end;

  { TIRCReceivers }

  //Preeminent Receivers
  TIRCReceivers = class(TCustomIRCReceivers)
  public
    procedure Parse(vData: string);
  end;

  { TIRCQueueReceivers }

  //Temporary commands, when received it will deleted
  TIRCQueueReceivers = class(TCustomIRCReceivers)
  end;

  { TIRCUserCommand }

  TIRCUserCommand = class(TObject)
  private
    FClient: TmnIRCClient;
    FName: string;
  protected
    procedure Send(S: string); virtual; abstract;
  public
    constructor Create(AName: string; AClient: TmnIRCClient);
    property Name: string read FName;
    property Client: TmnIRCClient read FClient;
  end;

  { TIRCUserCommands }

  TIRCUserCommands = class(TmnNamedObjectList<TIRCUserCommand>)
  private
    FClient: TmnIRCClient;
  public
    constructor Create(AClient: TmnIRCClient);
    property Client: TmnIRCClient read FClient;
  end;

  { TIRCRaw }

  TIRCRaw = class(TObject)
  public
    Text: string;
  end;

  { TIRCQueueRaws }

  TIRCQueueRaws = class(TmnObjectList<TIRCRaw>)
  end;

  TmnIRCState = (isDisconnected, isConnecting, isRegistering, isReady, isDisconnecting);

  TUserMode = (umInvisible, umOperator, umServerNotices, umWallops);
  TUserModes = set of TUserMode;

  TmnOnData = procedure(const Data: string) of object;

  { TmnIRCConnection }

  TmnIRCConnection = class(TmnClientConnection)
  private
    FIRCClient: TmnIRCClient;
    FHost: string;
    FPort: string;
  protected
    procedure DoReceive(const Data: string); virtual;
    procedure DoLog(const vData: string); virtual;
    procedure ProcessRaws;
    procedure Process; override;
    procedure SendRaw(S: string);
    property IRCClient: TmnIRCClient read FIRCClient;
  public
    constructor Create(vOwner: TmnConnections; vSocket: TmnConnectionStream); override;
    destructor Destroy; override;
    procedure Connect; override;
    property Host: string read FHost;
    property Port: string read FPort;
  end;

  TOnReceive = procedure(Sender: TObject; vChannel, vMSG: String) of object;
  TOnLogData = procedure(Sender: TObject; vLogType: TIRCLogType; vMsg: String) of object;

  { TmnIRCClient }

  TmnIRCClient = class(TObject)
  private
    FOnLog: TOnLogData;
    FOnReceive: TOnReceive;
    FOnUserModeChanged: TNotifyEvent;

    FPort: String;
    FHost: String;
    FPassword: String;
    FUsername: String;
    FRealName: String;
    FAltNick: String;
    FNick: String;

    FChangeNickTo: String;
    FCurrentNick: String;
    FCurrentUserModes: TUserModes;

    FUserModes: TUserModes;

    FState: TmnIRCState;
    FConnection: TmnIRCConnection;
    FReceivers: TIRCReceivers;
    FQueueReceivers: TIRCQueueReceivers;
    FQueueRaws: TIRCQueueRaws;
    FUserCommands: TIRCUserCommands;
    FLock: TCriticalSection;
    FUseUserCommands: Boolean;
    procedure SetAltNick(const Value: String);
    procedure SetNick(const Value: String);
    function GetNick: String;
    procedure SetPassword(const Value: String);
    procedure SetPort(const Value: String);
    procedure SetRealName(const Value: String);
    procedure SetHost(const Value: String);
    procedure Connected;
    procedure Disconnected;
    procedure SetState(const Value: TmnIRCState);
    procedure Reset;
    procedure SetUsername(const Value: String);
    function GetUserModes: TUserModes;
    procedure SetUserModes(const Value: TUserModes);
    function CreateUserModeCommand(NewModes: TUserModes): String;
  protected
    procedure ReceiveRaw(vData: String); virtual;
    procedure SendRaw(vData: String);

    procedure ChannelReceive(vChannel, vMsg: String); virtual;
    procedure Topic(vChannel, vTopic: String); virtual;
    procedure UserList(AUserList: TStrings); virtual;

    procedure UserModeChanged;
    procedure InitReceivers;
    procedure InitUserCommands;

  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;

    procedure Log(vLogType: TIRCLogType; Message: String);

    procedure ChannelSend(Channel, vMsg: String);

    procedure Join(Channel: String);
    procedure Notice(Destination, Text: String);
    procedure Quit(Reason: String);
    property State: TmnIRCState read FState;
    property Connection: TmnIRCConnection read FConnection;
    property Receivers: TIRCReceivers read FReceivers;
    property QueueReceivers: TIRCQueueReceivers read FQueueReceivers;
    property QueueRaws: TIRCQueueRaws read FQueueRaws;
    property UserCommands: TIRCUserCommands read FUserCommands;
    property Lock: TCriticalSection read FLock;
  public
    property Host: String read FHost write SetHost;
    property Port: String read FPort write SetPort;
    property Nick: String read GetNick write SetNick;
    property AltNick: String read FAltNick write SetAltNick;
    property RealName: String read FRealName write SetRealName;
    property Password: String read FPassword write SetPassword;
    property Username: String read FUsername write SetUsername;
    property UserModes: TUserModes read GetUserModes write SetUserModes;

    property UseUserCommands: Boolean read FUseUserCommands write FUseUserCommands default True;

    property OnLog: TOnLogData read FOnLog write FOnLog;
    property OnReceive: TOnReceive read FOnReceive write FOnReceive;
    property OnUserModeChanged: TNotifyEvent read FOnUserModeChanged write FOnUserModeChanged;
  end;

  { TPing_IRCReceiver }

  TPing_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TPRIVMSG_IRCReceiver }

  TPRIVMSG_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TMOTD_IRCReceiver }

  TMOTD_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TTOPIC_IRCReceiver }

  TTOPIC_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TWELCOME_IRCReceiver }

  TWELCOME_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TNICK_IRCReceiver }

  TNICK_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TMODE_IRCReceiver }

  TMODE_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TIRCUserName }

  TIRCUserName = class(TObject)
  public
    Name: string;
    Mode: string;//todo
  end;

  { TIRCUserNames }

  TIRCUserNames = class(TmnNamedObjectList<TIRCUserName>)
  private
  public
    Name: string; //Channel name
  end;

  { TIRCChannelUserNames }

  TIRCChannelUserNames = class(TmnNamedObjectList<TIRCUserNames>)
  public
  end;

  { TNAMREPLY_IRCReceiver }

  TNAMREPLY_IRCReceiver = class(TIRCReceiver)
  protected
    Users: TIRCChannelUserNames;
  public
    constructor Create(AClient: TmnIRCClient); override;
    destructor Destroy; override;
    function Accept(S: string): Boolean; override;
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TErrNicknameInUse_IRCReceiver }

  TErrNicknameInUse_IRCReceiver = class(TIRCReceiver)
  protected
    procedure DoReceive(vCommand: TIRCCommand); override;
  end;

  { TRAW_UserCommand }

  TRaw_UserCommand = class(TIRCUserCommand)
  protected
    procedure Send(S: string); override;
  public
  end;

  { TJoin_UserCommand }

  TJoin_UserCommand = class(TIRCUserCommand)
  protected
    procedure Send(S: string); override;
  public
  end;

implementation

uses
  SysUtils;

const
  sDefaultPort = '6667';
  sNickName = 'guest';

function ScanString(vStr: string; var vPos:Integer; out vCount: Integer; vChar: Char; vSkip: Boolean = False): Boolean;
var
  start: Integer;
begin
  start := vPos;
  while (vPos <= Length(vStr)) and (vStr[vPos] <> vChar) do
    Inc(vPos);
  vCount := vPos - start;
  { Remove any redundant }
  if vSkip then
    while (vPos <= Length(vStr)) and (vStr[vPos] = vChar) do
      Inc(vPos);
  Result := vCount > 0;
end;

function ExtractNickFromAddress(Address: String): String;
var
  EndOfNick: Integer;
begin
  Result := '';
  EndOfNick := Pos('!', Address);
  if EndOfNick > 0 then
    Result := Copy(Address, 1, EndOfNick - 1);
end;

{ TIRCReceivers }

procedure TIRCReceivers.Parse(vData: string);
type
  TParseState = (prefix, command);
var
  State: TParseState;
  p: Integer;
  Start, Count: Integer;
  //AName, ATime, AText, ASource: string;
  aCommand: TIRCCommand;
  aReceiver: TIRCReceiver;
  ABody: string;
begin
  if vData <> '' then
  begin
    aCommand := TIRCCommand.Create;
    try
      State := prefix;
      p := 1;
      while p < Length(vData) do
      begin
        { If the current token is a CTCP query, then look for the end of the query instead of the token separator }
        if vData[p] = '@' then
        begin
          Inc(p); //skip it
          Start := p;
          if ScanString(vData, p, Count, cTokenSeparator, True) then
            aCommand.FTime := MidStr(vData, Start, Count);
          //Inc(State); no do not increase it, we still except prefix
        end
        else if vData[p] = #1 then //CTCP idk what is this
        begin
          Inc(p); //skip it
          //Start := p;
          //find CTCP command and pass the full line
//          Break;
//          Inc(State); //nop
        end
        else if vData[p] = ':' then
        begin
          if State < command then
          begin
            Inc(p); //skip it
            Start := p;
            if ScanString(vData, p, Count, cTokenSeparator, True) then
              aCommand.FSource := MidStr(vData, Start, Count);
            Inc(State);
          end
          else
            raise Exception.Create('Wrong place of ":"');
        end
        else
        begin
          Start := p;
          if ScanString(vData, p, Count, cTokenSeparator, True) then
          begin
            aCommand.FName := MidStr(vData, Start, Count);
            ABody := MidStr(vData, Start + Count + 1, MaxInt);
            State := command;
            Inc(State);
          end;
          break;
        end;
      end;

      for aReceiver in Self do
      begin
        if aReceiver.Accept(aCommand.Name) then
        begin
          aReceiver.Parse(aCommand, ABody);
          aReceiver.Receive(aCommand);
        end;
      end;

    finally
      FreeAndNil(aCommand);
    end;
  end;
end;

{ TRaw_UserCommand }

procedure TRaw_UserCommand.Send(S: string);
begin
  Client.SendRaw(S);
end;

{ TNAMREPLY_IRCReceiver }

constructor TNAMREPLY_IRCReceiver.Create(AClient: TmnIRCClient);
begin
  inherited;
  Users := TIRCChannelUserNames.Create(True);
end;

destructor TNAMREPLY_IRCReceiver.Destroy;
begin
  inherited;
  FreeAndNil(Users);
end;

function TNAMREPLY_IRCReceiver.Accept(S: string): Boolean;
begin
  Result := inherited Accept(S);
  if S = IntToStr(IRC_RPL_ENDOFNAMES) then
  begin
    Result := True;
    //Pass the list and remove it
  end;
end;

procedure TNAMREPLY_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  // triggered by raw /NAMES
  //:server 353 zaher = #support user1
  //:server 353 zaherdirkey = ##support :user1 user2 user3
  Client.Lock.Enter;
  try
    if vCommand.Name <> IntToStr(IRC_RPL_ENDOFNAMES) then
      Client.Log(lgMsg, ' User: ' + vCommand.Params[2]);
  finally
    Client.Lock.Leave;
  end;
end;

{ TIRCUserCommands }

constructor TIRCUserCommands.Create(AClient: TmnIRCClient);
begin
  inherited Create(true);
  FClient := AClient;
end;

{ TIRCUserCommand }

constructor TIRCUserCommand.Create(AName: string; AClient: TmnIRCClient);
begin
  inherited Create;
  FClient := AClient;
  FName := AName;
end;

{ TJoin_UserCommand }

procedure TJoin_UserCommand.Send(S: string);
begin
  Client.SendRaw('JOIN ' + S);
end;

{ TErrNicknameInUse_IRCReceiver }

procedure TErrNicknameInUse_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  { Handle nick conflicts during the registration process. }
  with Client do
    if FState = isRegistering then
    begin
      if FChangeNickTo = FNick then
        SetNick(FAltNick)
      else
        Quit('Nick conflict');
    end;
end;

{ TMODE_IRCReceiver }

procedure TMODE_IRCReceiver.DoReceive(vCommand: TIRCCommand);
var
  Index: Integer;
  ModeString: String;
  AddMode: Boolean;
begin
  { Ignore channel mode changes.  Only interested in user mode changes. }
  with Client do
    if vCommand.Params[0] = FCurrentNick then
    begin
      { Copy the token for efficiency reasons. }
      ModeString := vCommand.Params[1];
      AddMode := True;
      for Index := 1 to Length(ModeString) do
      begin
        case ModeString[Index] of
          '+':
            AddMode := True;
          '-':
            AddMode := False;
          'i':
            if AddMode then
              FCurrentUserModes := FCurrentUserModes + [umInvisible]
            else
              FCurrentUserModes := FCurrentUserModes - [umInvisible];
          'o':
            if AddMode then
              FCurrentUserModes := FCurrentUserModes + [umOperator]
            else
              FCurrentUserModes := FCurrentUserModes - [umOperator];
          's':
            if AddMode then
              FCurrentUserModes := FCurrentUserModes + [umServerNotices]
            else
              FCurrentUserModes := FCurrentUserModes - [umServerNotices];
          'w':
            if AddMode then
              FCurrentUserModes := FCurrentUserModes + [umWallops]
            else
              FCurrentUserModes := FCurrentUserModes - [umWallops];
        end;
      end;
      UserModeChanged;
    end;
end;


{ TNICK_IRCReceiver }

procedure TNICK_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  { If it is our nick we are changing, then record the change. }
  if UpperCase(ExtractNickFromAddress(vCommand.Source)) = UpperCase(Client.FCurrentNick) then
    Client.FCurrentNick := vCommand.Params[0];
end;

{ TWELCOME_IRCReceiver }

procedure TWELCOME_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  with Client do
  begin
    FCurrentNick := vCommand.Params[0];
    SetState(isReady);
    if FUserModes <> [] then
      SendRaw(Format('MODE %s %s', [FCurrentNick, CreateUserModeCommand(FUserModes)]));
  end;
end;

{ TTOPIC_IRCReceiver }

procedure TTOPIC_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin

end;

{ TMOTD_IRCReceiver }

procedure TMOTD_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  Client.ChannelReceive('', vCommand.Text);
end;

{ TIRCReceiver }

procedure TIRCReceiver.Receive(vCommand: TIRCCommand);
begin
  DoReceive(vCommand);
  //Client.Log(lgMsg, Name + ' triggered');
end;

procedure TIRCReceiver.DoParse(vCommand: TIRCCommand; vData: string);
var
  p: Integer;
  Start, Count: Integer;
  procedure AddIt(s: string);
  begin
    vCommand.Params.Add(s);
  end;
begin
  vCommand.Params.Clear;
  if vData <> '' then
  begin
    p := 1;
    while p < Length(vData) do
    begin
      if vData[p] = ':' then
      begin
        vCommand.FText := MidStr(vData, p + 1, MaxInt);
        AddIt(vCommand.Text);
        Break;
      end
      else
      begin
        Start := p;
        ScanString(vData, p, Count, cTokenSeparator, True);
        if Count > 0 then
          AddIt(MidStr(vData, Start, Count));
      end;
    end;
  end;
end;

procedure TIRCReceiver.Parse(vCommand: TIRCCommand; vData: string);
begin
  DoParse(vCommand, vData);
  //Client.Log(lgMsg, '--->' + vData);
end;

function TIRCReceiver.Accept(S: string): Boolean;
begin
  Result := SameText(S, Name) or ((Code > 0) and SameText(S, IntToStr(Code)));
end;

constructor TIRCReceiver.Create(AClient: TmnIRCClient);
begin
  FClient := AClient;
end;

{ TPRIVMSG_IRCReceiver }

procedure TPRIVMSG_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  Client.ChannelReceive(vCommand.Params[0], vCommand.Params[1]);
end;

{ TPing_IRCReceiver }

procedure TPing_IRCReceiver.DoReceive(vCommand: TIRCCommand);
begin
  { SendDirect the PONG reply to the PING. }
  Client.SendRaw(Format('PONG %s', [vCommand.Params[0]]));
end;

{ TmnIRCConnection }

procedure TmnIRCConnection.DoReceive(const Data: string);
begin
  FIRCClient.ReceiveRaw(Data);
end;

procedure TmnIRCConnection.DoLog(const vData: string);
begin
  FIRCClient.Log(lgMsg, vData);
end;

procedure TmnIRCConnection.ProcessRaws;
var
  i: Integer;
begin
  FIRCClient.Lock.Enter;
  try
    for i := 0 to FIRCClient.QueueRaws.Count - 1 do
    begin
      SendRaw(FIRCClient.QueueRaws[i].Text);
    end;
    FIRCClient.QueueRaws.Clear;
  finally
    FIRCClient.Lock.Leave;
  end;
end;

procedure TmnIRCConnection.Process;
var
  Line: string;
begin
  inherited Process;
  ProcessRaws;
  if Stream.WaitToRead(Stream.Timeout) then
  begin
    Line := Trim(Stream.ReadLine);
    while Line <> '' do
    begin
      DoReceive(Line);
      Line := Trim(Stream.ReadLine);
    end;
  end;
end;

procedure TmnIRCConnection.SendRaw(S: string);
begin
  if Stream <> nil then
    Stream.WriteLine(S);
end;

constructor TmnIRCConnection.Create(vOwner: TmnConnections; vSocket: TmnConnectionStream);
begin
  inherited Create(vOwner, vSocket);
end;

destructor TmnIRCConnection.Destroy;
begin
  inherited;
end;

procedure TmnIRCConnection.Connect;
begin
  SetStream(TIRCSocketStream.Create(Host, Port, [soNoDelay, soConnectTimeout]));
  Stream.Timeout := WaitForEver;// 5 * 1000;
  Stream.EndOfLine := #10;
  inherited Connect;
end;

{ TIRCCommand }

constructor TIRCCommand.Create;
begin
  inherited;
  FParams := TStringList.Create;
end;

destructor TIRCCommand.Destroy;
begin
  FreeAndNil(FParams);
end;

procedure TIRCCommand.Parse(vData: string);
type
  TParseState = (prefix, command, params, text);
var
  State: TParseState;
  p: Integer;
  Start, Count: Integer;
  procedure AddIt(s: string);
  begin
    FParams.Add(s);
  end;
begin
  FRaw := vData;
  FParams.Clear;
  if vData <> '' then
  begin
    State := prefix;
    p := 1;
    while p < Length(vData) do
    begin
      { If the current token is a CTCP query, then look for the end of the
        query instead of the token separator. }
      if vData[p] = '@' then
      begin
        Inc(p); //skip it
        Start := p;
        ScanString(vData, p, Count, cTokenSeparator, True);
        if Count > 0 then
          FTime := MidStr(vData, Start, Count);
        //Inc(State); no do not increase it, we still except prefix
      end
      else if vData[p] = ':' then
      begin
        if State > prefix then
        begin
          FText := MidStr(vData, p + 1, MaxInt);
          AddIt(FText);
          State := text;
          Break;
        end
        else
        begin
          Inc(p); //skip it
          Start := p;
          ScanString(vData, p, Count, cTokenSeparator, True);
          if Count > 0 then
            FSource := MidStr(vData, Start, Count);
          Inc(State);
        end
      end
      else if vData[p] = #1 then //CTCP idk what is this
      begin
        Start := p;
        ScanString(vData, p, Count, #1);
        if Count > 0 then
          AddIt(MidStr(vData, Start, Count));
        Inc(State);
      end
      else
      begin
        Start := p;
        ScanString(vData, p, Count, cTokenSeparator, True);
        if Count > 0 then
        begin
          if State <= command then
          begin
            FName := MidStr(vData, Start, Count);
            State := command;
            Inc(State);
          end
          else
            AddIt(MidStr(vData, Start, Count));
        end
      end;
    end;
  end;
end;

{ TCustomIRCReceivers }

function TCustomIRCReceivers.Add(vName: String; vCode: Integer; AClass: TIRCReceiverClass): Integer;
var
  AReceiver: TIRCReceiver;
begin
  Result := IndexOfName(vName);
  if Result >= 0 then
  begin
    //not sure if we want more than one Receiver
  end;
  AReceiver := AClass.Create(Client);
  AReceiver.Name := vName;
  AReceiver.Code := vCode;
  Result := inherited Add(AReceiver);
end;

constructor TCustomIRCReceivers.Create(AClient: TmnIRCClient);
begin
  inherited Create(True);
  FClient := AClient;
end;

destructor TCustomIRCReceivers.Destroy;
begin
  inherited;
end;

procedure TCustomIRCReceivers.Receive(ACommand: TIRCCommand);
var
  AReceiver: TIRCReceiver;
begin
  for AReceiver in Self do
  begin
    if AReceiver.Accept(ACommand.Name) then
      AReceiver.Receive(ACommand);
  end;
end;

{ TmnIRCClient }

procedure TmnIRCClient.Disconnect;
begin
  { Try to leave nicely if we can }
  if FState = isReady then
  begin
    SetState(isDisconnecting);
    SendRaw('QUIT');
  end
  else
  begin
    SetState(isDisconnecting);
    if FConnection.Active then
      FConnection.Close;
    Disconnected;
  end;
end;

procedure TmnIRCClient.Connect;
begin
  if (FState = isDisconnected) then
  begin
    FCurrentNick := FNick;
    FChangeNickTo := '';
    SetState(isConnecting);
    Connection.FHost := Host;
    Connection.FPort := Port;
    Connection.Connect; //move it to Process
    Connection.Start;
    Connected;
  end;
end;

constructor TmnIRCClient.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FConnection := TmnIRCConnection.Create(nil, nil);
  FConnection.FIRCClient := Self;
  FConnection.FreeOnTerminate := False;
  FUseUserCommands := True;
  FHost := 'localhost';
  FPort := sDefaultPort;
  FNick := sNickName;
  FAltNick := '';
  FRealName := '';
  FUsername := 'username';
  FPassword := '';
  FState := isDisconnected;
  FReceivers := TIRCReceivers.Create(Self);
  FQueueReceivers := TIRCQueueReceivers.Create(Self);
  FUserCommands :=TIRCUserCommands.Create(Self);
  FQueueRaws := TIRCQueueRaws.Create(True);
  InitReceivers;
  InitUserCommands;
end;

destructor TmnIRCClient.Destroy;
begin
  Reset;
  FreeAndNil(FConnection); //+
  FreeAndNil(FUserCommands);
  FreeAndNil(FQueueRaws);
  FreeAndNil(FReceivers);
  FreeAndNil(FQueueReceivers);
  FreeAndNil(FLock);
  inherited;
end;

procedure TmnIRCClient.Reset;
begin
  SetState(isDisconnecting);
  if Assigned(FConnection) and (FConnection.Connected) then
    FConnection.Close;
end;

procedure TmnIRCClient.SendRaw(vData: String);
begin
  if Assigned(FConnection) and (FState in [isRegistering, isReady]) then
    FConnection.SendRaw(vData);
  Log(lgSend, vData)
end;

procedure TmnIRCClient.Log(vLogType: TIRCLogType; Message: String);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, vLogType, Message);
end;

procedure TmnIRCClient.ChannelSend(Channel, vMsg: String);
var
  aCMD: TIRCUserCommand;
  aCMDProcessed: Boolean;
  s, m: string;
  p, c: Integer;
begin
  aCMDProcessed := False;
  if FUseUserCommands and (UserCommands.Count > 0) and (LeftStr(vMsg, 1) = '/') then
  begin
    p := 2;
    if ScanString(vMsg, p, c, ' ', true) then
    begin
      m := MidStr(vMsg, 2, c);
      s := MidStr(vMsg,  3 + c, MaxInt);
      for aCmd in UserCommands do
      begin
        if SameText(aCmd.Name, m) then
        begin
          aCmd.Send(s);
          aCMDProcessed := True;
        end;
      end;
    end;
  end;

  if not aCMDProcessed then
    SendRaw(Format('PRIVMSG %s :%s', [Channel, vMsg]));
end;

procedure TmnIRCClient.Join(Channel: String);
begin
  SendRaw(Format('JOIN %s', [Channel]));
end;

procedure TmnIRCClient.Notice(Destination, Text: String);
begin
  SendRaw(Format('NOTICE %s :%s', [Destination, Text]));
end;

procedure TmnIRCClient.Disconnected;
begin
  SetState(isDisconnected);
end;

procedure TmnIRCClient.Connected;
begin
  SetState(isRegistering);
  { If a password exists, SendDirect it first }
  if FPassword <> '' then
    SendRaw(Format('PASS %s', [FPassword]));
  { SendDirect nick. }
  SetNick(FNick);
  { SendDirect registration. }
  SendRaw(Format('USER %s %s %s :%s', [FUsername, FUsername, FHost, FRealName]));
end;

procedure TmnIRCClient.SetAltNick(const Value: String);
begin
  FAltNick := Value;
end;

procedure TmnIRCClient.SetNick(const Value: String);
begin
  if Value <> '' then
  begin
    if FState in [isRegistering, isReady] then
    begin
      if Value <> FChangeNickTo then
      begin
        SendRaw(Format('NICK %s', [Value]));
        FChangeNickTo := Value;
      end;
    end
    else
      FNick := Value;
  end;
end;

procedure TmnIRCClient.SetPassword(const Value: String);
begin
  FPassword := Value;
end;

procedure TmnIRCClient.SetPort(const Value: String);
begin
  FPort := Value;
end;

procedure TmnIRCClient.SetRealName(const Value: String);
begin
  FRealName := Value;
end;

procedure TmnIRCClient.SetHost(const Value: String);
begin
  FHost := Value;
end;

procedure TmnIRCClient.SetUsername(const Value: String);
begin
  FUsername := Value;
end;

procedure TmnIRCClient.SetState(const Value: TmnIRCState);
begin
  if Value <> FState then
  begin
    FState := Value;
  end;
end;

function TmnIRCClient.GetUserModes: TUserModes;
begin
  if FState in [isRegistering, isReady] then
    Result := FCurrentUserModes
  else
    Result := FUserModes;
end;

procedure TmnIRCClient.SetUserModes(const Value: TUserModes);
var
  ModeString: String;
begin
  if FState in [isRegistering, isReady] then
  begin
    ModeString := CreateUserModeCommand(Value);
    if Length(ModeString) > 0 then
      SendRaw(Format('MODE %s %s', [FCurrentNick, ModeString]));
  end
  else
  begin
    FUserModes := Value;
  end;
end;

procedure TmnIRCClient.ReceiveRaw(vData: String);
{var
  ACommand: TIRCCommand;}
begin
  Log(lgReceive, vData);
  Receivers.Parse(vData);
  {ACommand := TIRCCommand.Create;
  ACommand.Parse(vData);
  try
    Receivers.Receive(ACommand);
  finally
    FreeAndNil(ACommand);
  end;}
end;

procedure TmnIRCClient.ChannelReceive(vChannel, vMsg: String);
begin
  if Assigned(FOnReceive) then
    FOnReceive(Self, vChannel, vMsg);
end;

procedure TmnIRCClient.Topic(vChannel, vTopic: String);
begin

end;

procedure TmnIRCClient.UserList(AUserList: TStrings);
begin

end;

procedure TmnIRCClient.UserModeChanged;
begin
  if Assigned(FOnUserModeChanged) then
    FOnUserModeChanged(Self);
end;

procedure TmnIRCClient.Quit(Reason: String);
begin
  SendRaw(Format('QUIT :%s', [Reason]));
end;

procedure TmnIRCClient.InitReceivers;
begin
  Receivers.Add('PRIVMSG', 0, TPRIVMSG_IRCReceiver);
  Receivers.Add('PING', 0, TPING_IRCReceiver);
  Receivers.Add('MOTD', IRC_RPL_MOTD, TMOTD_IRCReceiver);
  Receivers.Add('TOPIC', IRC_RPL_TOPIC, TTOPIC_IRCReceiver);
  Receivers.Add('NICK', 0, TNICK_IRCReceiver);
  Receivers.Add('WELCOME', IRC_RPL_WELCOME, TWELCOME_IRCReceiver);
  Receivers.Add('MODE', 0, TMODE_IRCReceiver);
  Receivers.Add('NAMREPLY', IRC_RPL_NAMREPLY, TNAMREPLY_IRCReceiver);
  Receivers.Add('ERR_NICKNAMEINUSE', 0, TErrNicknameInUse_IRCReceiver);
end;

procedure TmnIRCClient.InitUserCommands;
begin
  UserCommands.Add(TRaw_UserCommand.Create('Raw', Self));
  UserCommands.Add(TJoin_UserCommand.Create('Join', Self));
end;

function TmnIRCClient.GetNick: String;
begin
  if FState in [isRegistering, isReady] then
    Result := FCurrentNick
  else
    Result := FNick;
end;

{ Create the mode command string to SendDirect to the server to modify the user's
  mode.  For example, "+i-s" to add invisible and remove server notices. }
function TmnIRCClient.CreateUserModeCommand(NewModes: TUserModes): String;
const
  ModeChars: array [umInvisible..umWallops] of Char = ('i', 'o', 's', 'w');
var
  ModeDiff: TUserModes;
  Mode: TUserMode;
begin
  Result := '';
  { Calculate user modes to remove. }
  ModeDiff := FCurrentUserModes - NewModes;
  if ModeDiff <> [] then
  begin
    Result := Result + '-';
    for Mode := Low(TUserMode) to High(TUserMode) do
    begin
      if Mode in ModeDiff then
        Result := Result + ModeChars[Mode];
    end;
  end;
  { Calculate user modes to add. }
  ModeDiff := NewModes - FCurrentUserModes;
  if ModeDiff <> [] then
  begin
    Result := Result + '+';
    for Mode := Low(TUserMode) to High(TUserMode) do
    begin
      if Mode in ModeDiff then
        Result := Result + ModeChars[Mode];
    end;
  end;
end;

end.
