unit IoC;

interface

uses
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.SysUtils;

type
  EIoCException = class(Exception);
  EBeanException = class(EIoCException);
  EIoCBeanNotFoundException = class(EIoCException);
  EScopedNotFoundException = class(EIoCBeanNotFoundException);
  ESingletonNotFoundException = class(EIoCBeanNotFoundException);

  TIoCRegistry = class;
  TSessionBeanContainer = class;
  TSingletonBeanContainerHolder = class;
  IBeanFactory = interface;
  TBeanFactoryContext = class;

  TBeanValue = TValue;
  TBeanFactoryCallback = reference to function(Ctx: TBeanFactoryContext): TBeanValue;

  TIdentityHelper = record
    public
      class function Make(const TypeInfo: PTypeInfo): String;
        overload; static; inline;

      class function Make(const TypeInfo: PTypeInfo; const Qualifier: String): String;
        overload; static; inline;
    end;

  TBean = record
    strict private
      FValue: TValue;
    public
      function Unwrap<T>(): T;
      procedure Close();
      constructor Wrap(const Value: TValue);
      class operator Finalize(var Dest: TBean);
    end;

  ILogger = interface
    procedure Debug(const Message: String);
  end;

  ISingletonBeanContainer = interface
    ['{AF7AF191-9441-4F82-BCF7-D09519713F9B}']
    function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
  end;

  IBeanFactory = interface
    ['{3D007D34-4060-4B81-A24B-3BFE1E36AAA8}']
    function CreateBean(const Context: TBeanFactoryContext; const Identity: String): TBean;
  end;

  IBeanContainer = interface(ISingletonBeanContainer)
    ['{BFD58202-8239-4CFE-9AE2-B4CEB625BE2E}']
    function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
    function TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
    function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
  end;

  //
  // Allows parts of IBeanContainer implementation to be accessible from
  // callback factory function.
  //
  TBeanFactoryContext = class
    strict private
      FBeanContainer: TSessionBeanContainer;
    public
      function AnyScoped<T>(): T;
      function AnySingleton<T>(): T;
      function Any<T>(): T;
    public
      constructor Create(const BeanContainer: TSessionBeanContainer);
    end;

  TSessionBeanContainer = class(TInterfacedObject, IBeanContainer)
    type
      TBeanHashTable = TDictionary<String, TBean>;
    strict private
      FBeanFactory: IBeanFactory;
      FScopedTable: TBeanHashTable;
      FTransientTable: TBeanHashTable;
      FBeanFactoryContext: TBeanFactoryContext;
    protected // internal interfaces
      function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
      function TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
      function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
      function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
    public // public interfaces
      function GetScoped<T>(): T; overload;
      function GetScoped<T>(const Qualifier: String): T; overload;
      function GetAny<T>(): T; overload;
      function GetAny<T>(const Qualifier: String): T; overload;
      function GetSingleton<T>(): T; overload;
      function GetSingleton<T>(const Qualifier: String): T; overload;
      function GetTransient<T>(): T; overload;
      function GetTransient<T>(const Qualifier: String): T; overload;
    public
      constructor Create(); overload;
      constructor Create(const BeanFactory: IBeanFactory); overload;
      destructor Destroy(); override;
    end;

  TCallbackBeanFactory = class(TInterfacedObject, IBeanFactory)
    type
      TBeanFactoryCallbackHashTable = TDictionary<String, TBeanFactoryCallback>;
    strict private
      FBeanFactoryCallbackTable: TBeanFactoryCallbackHashTable;
    public
      procedure RegisterCallback(const Identity: String; Callback: TBeanFactoryCallback);
      function CreateBean(const Context: TBeanFactoryContext; const Identity: String): TBean;
    public
      constructor Create();
      destructor Destroy(); override;
    end;

  TIoCRegistry = class
    strict private
      class var _DefaultBeanFactory: IBeanFactory;
    public
      class function RegisterBeanFactory<T>(const Qualifier: String; Callback: TBeanFactoryCallback): TIoCRegistry;
        overload;
      class function RegisterBeanFactory<T>(Callback: TBeanFactoryCallback): TIoCRegistry;
        overload;
      class function GetDefaultBeanFactory(): IBeanFactory;
      class constructor Initialize();
      class destructor Unitialize();
  end;

  TSingletonBeanContainerHolder = class
    strict private
      class var _SingletonBeanContainer: IBeanContainer;
    public
      class function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
      class constructor Initialize();
      class destructor Unitialize();
    end;

implementation

{$REGION 'TSessionBeanContainer'}

constructor TSessionBeanContainer.Create();
begin
  Create(TIoCRegistry.GetDefaultBeanFactory());
end;

constructor TSessionBeanContainer.Create(const BeanFactory: IBeanFactory);
begin
  FScopedTable := TBeanHashTable.Create();
  FTransientTable := TBeanHashTable.Create();
  FBeanFactoryContext := TBeanFactoryContext.Create(Self);
  FBeanFactory := BeanFactory;
end;

function TSessionBeanContainer.GetScoped<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FScopedTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetAny<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if not TryGetAny(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FTransientTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetAny<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if not TryGetAny(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FTransientTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetScoped<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FScopedTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetTransient<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if not TryGetTransient(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FTransientTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetTransient<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if not TryGetTransient(lIdentity, lBean) then
  begin
    lBean := FBeanFactory.CreateBean(FBeanFactoryContext, lIdentity);
    FTransientTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetSingleton<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if TryGetSingleton(lIdentity, lBean) then
  begin
    Result := lBean.Unwrap<T>();
    Exit;
  end;

  raise ESingletonNotFoundException.Create(lIdentity);
end;

function TSessionBeanContainer.GetSingleton<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if TryGetSingleton(lIdentity, lBean) then
  begin
    Result := lBean.Unwrap<T>();
    Exit;
  end;


  raise ESingletonNotFoundException.Create(lIdentity);
end;

function TSessionBeanContainer.TryGetAny(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := True;

  if TryGetScoped(Identity, Bean) then
    Exit;

  if TryGetTransient(Identity, Bean) then
    Exit;

  if TryGetSingleton(Identity, Bean) then
    Exit;

  Result := False;
end;

function TSessionBeanContainer.TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := FScopedTable.TryGetValue(Identity, Bean);
end;

function TSessionBeanContainer.TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := TSingletonBeanContainerHolder.TryGetSingleton(Identity,Bean);
end;

function TSessionBeanContainer.TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := FTransientTable.TryGetValue(Identity, Bean);
end;

destructor TSessionBeanContainer.Destroy();
begin
  FreeAndNil(FScopedTable);
  FreeAndNil(FTransientTable);
  FreeAndNil(FBeanFactoryContext);
  inherited;
end;

{$ENDREGION}

{$REGION 'TIdentityHelper'}

class function TIdentityHelper.Make(const TypeInfo: PTypeInfo; const Qualifier: String): String;
begin
  Result := Format('%s [%s]', [String(TypeInfo.Name), Qualifier]);
end;

class function TIdentityHelper.Make(const TypeInfo: PTypeInfo): String;
begin
  Result := String(TypeInfo.Name);
end;

{$ENDREGION}

{$REGION 'TSingletonBeanContainerHolder'}

class constructor TSingletonBeanContainerHolder.Initialize();
begin
  _SingletonBeanContainer := TSessionBeanContainer.Create();
end;

class function TSingletonBeanContainerHolder.TryGetSingleton(
  const Identity: String;
  out Bean: TBean): Boolean;
begin
  Result := _SingletonBeanContainer.TryGetScoped(Identity, Bean);
end;

class destructor TSingletonBeanContainerHolder.Unitialize();
begin
  _SingletonBeanContainer := nil;
end;

{$ENDREGION}

{$REGION 'TBean'}

constructor TBean.Wrap(const Value: TValue);
begin
  if Value.IsEmpty then
    raise EBeanException.Create('Unable to wrap null bean.');

  FValue := Value;
end;

function TBean.Unwrap<T>(): T;
var
  lCastedValue: TValue;
  lUnwrapTypeInfo, lBeanTypeInfo: PTypeInfo;
  lBeanTypeName, lUnwrapTypeName: String;
begin
  lBeanTypeInfo := FValue.TypeInfo;
  lUnwrapTypeInfo := TypeInfo(T);

  if lUnwrapTypeInfo = lBeanTypeInfo then
  begin
    FValue.ExtractRawDataNoCopy(@Result);
    Exit;
  end;

  lBeanTypeName := String(lBeanTypeInfo.Name);
  lUnwrapTypeName := String(lUnwrapTypeInfo.Name);

  if lUnwrapTypeInfo.Kind = tkInterface then
  begin
    if Supports(FValue.AsInterface,
                GetTypeData(lUnwrapTypeInfo).GUID,
                Result) then
      Exit;

     raise EBeanException.CreateFmt(
            'Failed to unwrap bean. "%s" does not supports "%s"',
            [lBeanTypeName, lUnwrapTypeName]);
  end;

  if lUnwrapTypeInfo.Kind = tkClass then
  begin
    try
      lCastedValue := FValue.Cast<T>();

      if lCastedValue.IsEmpty then
        raise EInvalidCast.Create('casted to Empty value.');

      lCastedValue.ExtractRawDataNoCopy(@Result);
    except
      on Ex: Exception do
      begin
        if Ex is EInvalidCast then
          raise EBeanException.CreateFmt(
            'Failed to unwrap bean. Could not cast "%s" into "%s"',
            [lBeanTypeName, lUnwrapTypeName]);

        raise EBeanException.CreateFmt(
            'Failed to unwrap bean. %s', [Ex.Message]);
      end;
    end;
  end;
end;

procedure TBean.Close();
begin { future } end;

class operator TBean.Finalize(var Dest: TBean);
begin
  Dest.Close();
end;

{$ENDREGION}

{$Region 'TBeanFactoryContext'}

function TBeanFactoryContext.Any<T>(): T;
begin
  Result := FBeanContainer.GetAny<T>();
end;

function TBeanFactoryContext.AnyScoped<T>(): T;
begin
  Result := FBeanContainer.GetScoped<T>();
end;

function TBeanFactoryContext.AnySingleton<T>(): T;
begin
  Result := FBeanContainer.GetSingleton<T>();
end;

constructor TBeanFactoryContext.Create(const BeanContainer: TSessionBeanContainer);
begin
  FBeanContainer := BeanContainer;
end;

{$ENDREGION}

{$REGION 'TIoCRegistry'}

class constructor TIoCRegistry.Initialize();
begin
  _DefaultBeanFactory := TCallbackBeanFactory.Create();
end;

class function TIoCRegistry.GetDefaultBeanFactory(): IBeanFactory;
begin
  Result := _DefaultBeanFactory;
end;

{$WARN NO_RETVAL OFF}
class function TIoCRegistry.RegisterBeanFactory<T>(Callback: TBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));
  (_DefaultBeanFactory as TCallbackBeanFactory).RegisterCallback(lIdentity, Callback);
end;

class function TIoCRegistry.RegisterBeanFactory<T>(const Qualifier: String; Callback: TBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);
  (_DefaultBeanFactory as TCallbackBeanFactory).RegisterCallback(lIdentity, Callback);
end;
{$WARN NO_RETVAL ON}

class destructor TIoCRegistry.Unitialize();
begin
  _DefaultBeanFactory := nil;
end;

{$ENDREGION}

{$REGION 'TCallbackBeanFactory'}

constructor TCallbackBeanFactory.Create();
begin
  FBeanFactoryCallbackTable := TBeanFactoryCallbackHashTable.Create();
end;

function TCallbackBeanFactory.CreateBean(const Context: TBeanFactoryContext; const Identity: String): TBean;
var
  lCallback: TBeanFactoryCallback;
begin
  if FBeanFactoryCallbackTable.TryGetValue(Identity, lCallback) then
  begin
    Result := TBean.Wrap(lCallback(Context));
    Exit;
  end;

  raise EBeanException.CreateFmt('Failed to create bean. Unable to resolve a callback for : %s', [Identity]);
end;

destructor TCallbackBeanFactory.Destroy();
begin
  FreeAndNil(FBeanFactoryCallbackTable);
  inherited;
end;

procedure TCallbackBeanFactory.RegisterCallback(const Identity: String; Callback: TBeanFactoryCallback);
begin
  FBeanFactoryCallbackTable.AddOrSetValue(Identity, Callback);
end;

{$ENDREGION}

end.
