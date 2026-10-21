unit IoC.Proxy;

interface

uses
  System.Rtti,
  System.TypInfo,
  System.SysUtils;

type
  EProxyException = class(Exception);

  IInterceptor = interface;

  TProxyInvokeChain = record
    strict private
      FResult: TValue;
      FArguments: TArray<TValue>;
      FInterceptors: TArray<IInterceptor>;
      FCountInterceptors: Integer;
      FCurrentInterceptor: Integer;
      FMethod: TRttiMethod;
      FThing: TValue;
    private
      constructor Create(const Thing: TValue;
                         const Method: TRttiMethod;
                         const Arguments: TArray<TValue>;
                         const Interceptors: TArray<IInterceptor>);
    public
      procedure Proceed();
      procedure SetResult(const Value: TValue);
      procedure SetArguments(const Arguments: TArray<TValue>);
      function ThingAs<T>(): T;
    public
      property Thing: TValue read FThing;
      property Method: TRttiMethod read FMethod;
      property Arguments: TArray<TValue> read FArguments;
      property Result: TValue read FResult;
    end;

  IInterceptor = interface
    procedure Handle(const Chain: TProxyInvokeChain);
  end;

  TInterfaceProxyImplementor = class(TVirtualInterface, IInterceptor)
    strict private
      FThing: TValue;
      FInterceptors: TArray<IInterceptor>;
    private
      procedure Handle(const Chain: TProxyInvokeChain);
      procedure HandleInvokeImpl(Method: TRttiMethod;
                                 const Args: TArray<TValue>;
                                 out Result: TValue);
    public
      function GetProxy<T>(): T;
      function GetValueProxy(const TypeInfo: PTypeInfo): TValue;
      constructor Create(
        const Thing: TValue;
        const Interceptors: TArray<IInterceptor>);
    end;

  TProxy = record
    private
      class procedure CheckPreconditionProxyType<T>(); static;
    public
      class function CreateStub(
        const TypeInfo: PTypeInfo;
        const Interceptor: IInterceptor): TValue; overload; static;

      class function CreateProxyFor(
        const Thing: TValue;
        const TypeInfo: PTypeInfo;
        const Interceptors: TArray<IInterceptor>): TValue; overload; static;

      class function CreateStub<T: IInterface>(
        const Interceptor: IInterceptor): T; overload; static;

      class function CreateStub<T: IInterface>(
        const Interceptors: TArray<IInterceptor>): T; overload; static;

      class function CreateProxyFor<T: IInterface>(
        Thing: T;
        const Interceptors: TArray<IInterceptor>): T; overload; static;

      class function CreateProxyFor<T: IInterface>(
        Thing: T;
        const Interceptor: IInterceptor): T; overload; static;
    end;


implementation

{ TProxy }

class function TProxy.CreateProxyFor<T>(
  Thing: T;
  const Interceptors: TArray<IInterceptor>): T;
begin
  CheckPreconditionProxyType<T>();

  Result := TInterfaceProxyImplementor
    .Create(TValue.From<T>(Thing), Interceptors)
    .GetProxy<T>();
end;

class function TProxy.CreateProxyFor(
  const Thing: TValue;
  const TypeInfo: PTypeInfo;
  const Interceptors: TArray<IInterceptor>): TValue;
begin
  Result := TInterfaceProxyImplementor
    .Create(Thing, Interceptors)
    .GetValueProxy(TypeInfo);
end;

class function TProxy.CreateProxyFor<T>(
  Thing: T;
  const Interceptor: IInterceptor): T;
begin
  CheckPreconditionProxyType<T>();

  Result := TInterfaceProxyImplementor
    .Create(TValue.From<T>(Thing), [Interceptor])
    .GetProxy<T>();
end;

class function TProxy.CreateStub<T>(
  const Interceptor: IInterceptor): T;
var
  lStubValue: TValue;
begin
  CheckPreconditionProxyType<T>();
  TValue.Make(nil, TypeInfo(T), lStubValue);
  
  Result := TInterfaceProxyImplementor
    .Create(lStubValue, [Interceptor])
    .GetProxy<T>();
end;

class function TProxy.CreateStub(
  const TypeInfo: PTypeInfo;
  const Interceptor: IInterceptor): TValue;
var
  lStubValue: TValue;
begin
  TValue.Make(nil, TypeInfo, lStubValue);
  
  Result := TInterfaceProxyImplementor
    .Create(lStubValue, [Interceptor])
    .GetValueProxy(TypeInfo);
end;

class function TProxy.CreateStub<T>(
  const Interceptors: TArray<IInterceptor>): T;
var
  lStubValue: TValue;
begin
  CheckPreconditionProxyType<T>();
  TValue.Make(nil, TypeInfo(T), lStubValue);
  
  Result := TInterfaceProxyImplementor
    .Create(lStubValue, Interceptors)
    .GetProxy<T>();
end;


class procedure TProxy.CheckPreconditionProxyType<T>();
var
  lTypeInfo: PTypeInfo;
begin
  lTypeInfo := TypeInfo(T);

  if lTypeInfo.Kind = tkInterface then
    Exit;

  raise EProxyException.CreateFmt(
    'Unable to create a proxy: %s != interface.', [lTypeInfo]);
end;

{ TInterfaceProxyImplementor }

constructor TInterfaceProxyImplementor.Create(
  const Thing: TValue;
  const Interceptors: TArray<IInterceptor>);
begin
  FInterceptors := Interceptors;

  if not Thing.IsEmpty then
  begin
    FThing := Thing;
    FInterceptors := FInterceptors + [Self];
  end
  else if Length(FInterceptors) = 0 then
    raise EProxyException.Create('Stub proxy must implement at least one IInterceptor.');

  inherited Create(FThing.TypeInfo, HandleInvokeImpl);
end;

procedure TInterfaceProxyImplementor.Handle(
  const Chain: TProxyInvokeChain);
begin
  with Chain do
     SetResult(Method.Invoke(Thing, Arguments));
end;

procedure TInterfaceProxyImplementor.HandleInvokeImpl(
  Method: TRttiMethod;
  const Args: TArray<TValue>;
  out Result: TValue);
var
  lArguments: TArray<TValue>;
  lInvokeChain: TProxyInvokeChain;
begin
  lArguments := Args;
  Delete(lArguments, 0, 1);

  lInvokeChain := TProxyInvokeChain.Create(
    FThing,
    Method,
    lArguments,
    FInterceptors);

  lInvokeChain.Proceed();
  Result := lInvokeChain.Result;
end;

function TInterfaceProxyImplementor.GetValueProxy(
  const TypeInfo: PTypeInfo): TValue;
var
  lUnknown: IUnknown;
begin
  Supports(Self, GetTypeData(TypeInfo).GUID, lUnknown);
  TValue.Make(PInterface(@lUnknown), TypeInfo, Result);
end;

function TInterfaceProxyImplementor.GetProxy<T>(): T;
begin
  Supports(Self, GetTypeData(TypeInfo(T)).GUID, Result);
end;

{ TProxyInvokeChain }

constructor TProxyInvokeChain.Create(
  const Thing: TValue;
  const Method: TRttiMethod;
  const Arguments: TArray<TValue>;
  const Interceptors: TArray<IInterceptor>);
begin
  FThing := Thing;
  FMethod := Method;
  FArguments := Arguments;
  FInterceptors := Interceptors;
  FCountInterceptors := Length(FInterceptors);
  FCurrentInterceptor := -1;
end;

procedure TProxyInvokeChain.SetArguments(const Arguments: TArray<TValue>);
begin
  FArguments := Arguments;
end;

procedure TProxyInvokeChain.SetResult(const Value: TValue);
begin
  FResult := Value;
end;

procedure TProxyInvokeChain.Proceed();
begin
  if FCurrentInterceptor < FCountInterceptors then
  begin
    Inc(FCurrentInterceptor);
    FInterceptors[FCurrentInterceptor].Handle(Self);
  end;
end;

function TProxyInvokeChain.ThingAs<T>(): T;
begin
  Result := FThing.AsType<T>(False);
end;

end.
