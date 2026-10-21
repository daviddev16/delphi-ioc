unit IoC;

interface

uses
  IoC.Proxy,
  System.Rtti,
  System.TypInfo,
  System.SyncObjs,
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

  TBeanValue = TValue;
  TBeanFactoryCallback<T> = reference to function(Ctx: T): TBeanValue;

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
      function GetTypeInfo(): PTypeInfo;
      procedure Close();
      constructor Wrap(const Value: TValue);
      class operator Finalize(var Dest: TBean);
      property Value: TValue read FValue;
    end;

  TAbstractBeanFactoryContext = class abstract
    strict private
      FBeanContainer: TSessionBeanContainer;
    public
      constructor Create(const BeanContainer: TSessionBeanContainer);
    protected
      property Container: TSessionBeanContainer read FBeanContainer;
    end;

  TSingletonBeanFactoryContext = class(TAbstractBeanFactoryContext)
    public
      function Singleton<T>(): T;
    end;

  TSingletonBeanFactoryCallback = TBeanFactoryCallback<TSingletonBeanFactoryContext>;

  TScopedBeanFactoryContext = class(TAbstractBeanFactoryContext)
    public
      function Singleton<T>(): T;
      function Scoped<T>(): T;
      function Transient<T>(): T;
    end;

  TScopedBeanFactoryCallback = TBeanFactoryCallback<TScopedBeanFactoryContext>;

  ISingletonBeanContainer = interface
    ['{AF7AF191-9441-4F82-BCF7-D09519713F9B}']
    function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
  end;

  IBeanFactory = interface
    ['{3D007D34-4060-4B81-A24B-3BFE1E36AAA8}']
    function CreateBean(
      const Identity: String;
      const Ctx: TScopedBeanFactoryContext): TBean;

    function CreateSingletonBean(
      const Identity: String;
      const Ctx: TSingletonBeanFactoryContext): TBean;
  end;

  IBeanContainer = interface(ISingletonBeanContainer)
    ['{BFD58202-8239-4CFE-9AE2-B4CEB625BE2E}']
    function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
    function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
    function TryInjectScoped(const Identity: String; const Bean: TBean): Boolean;
  end;

  TSessionBeanContainer = class(TInterfacedObject, IBeanContainer)
    type
      TBeanHashTable = TDictionary<String, TBean>;
    strict private
      FBeanFactory: IBeanFactory;
      FScopedTable: TBeanHashTable;
    protected // internal interfaces
      function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
      function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
      function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
      function TryInjectScoped(const Identity: String; const Bean: TBean): Boolean;
    public // public interfaces
      function GetScoped<T>(): T; overload;
      function GetScoped<T>(const Qualifier: String): T; overload;
      function GetSingleton<T>(): T; overload;
      function GetSingleton<T>(const Qualifier: String): T; overload;
      function GetTransient<T>(): T; overload;
      function GetTransient<T>(const Qualifier: String): T; overload;
      procedure InjectScoped<T>(const Qualifier: String; const Thing: T);
    public
      constructor Create(); overload;
      constructor Create(const BeanFactory: IBeanFactory); overload;
      destructor Destroy(); override;
    end;

  TBeanFactoryDefinition<C> = record
    private
      Interceptors: TArray<IInterceptor>;
      Callback: C;
      Qualifier: String;
      TypeInfo: PTypeInfo;
    public
      function HasInterception(): Boolean;
    end;

  TCallbackBeanFactory = class(TInterfacedObject, IBeanFactory)
    strict private
      FScopedBeanFactoryDefinitions: TDictionary<String,
        TBeanFactoryDefinition<TScopedBeanFactoryCallback>>;

      FSingletonBeanFactoryDefinitions: TDictionary<String,
        TBeanFactoryDefinition<TSingletonBeanFactoryCallback>>;
    public
      procedure RegisterScopedBeanFactoryCallback(
          const Identity: String;
          const Definition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>);

      procedure RegisterSingletonBeanFactoryCallback(
          const Identity: String;
          const Definition: TBeanFactoryDefinition<TSingletonBeanFactoryCallback>);

      function CreateBean(
        const Identity: String;
        const Ctx: TScopedBeanFactoryContext): TBean;

      function CreateSingletonBean(
        const Identity: String;
        const Ctx: TSingletonBeanFactoryContext): TBean;
    public
      constructor Create();
      destructor Destroy(); override;
    end;

  TBeanFactoryProxifier = class
    public
      class procedure ProxyBean(
        const WrappedBean: TBean;
        const Interceptors: TArray<IInterceptor>;
        const InterfaceTypeInfo: PTypeInfo;
        out ProxifiedBean: TBean);
    end;

  TIoCRegistry = class
    strict private
      class var _DefaultBeanFactory: IBeanFactory;
    public
      class function RegisterScopedBeanFactory<T>(
        Callback: TScopedBeanFactoryCallback): TIoCRegistry; overload;

      class function RegisterScopedBeanFactory<T>(
        const Qualifier: String;
        Callback: TScopedBeanFactoryCallback): TIoCRegistry; overload;

      class function RegisterScopedBeanFactory<T>(
        const Qualifier: String;
        Callback: TScopedBeanFactoryCallback;
        const Interceptors: TArray<IInterceptor>): TIoCRegistry; overload;

      class function RegisterScopedBeanFactory<T>(
        Callback: TScopedBeanFactoryCallback;
        const Interceptors: TArray<IInterceptor>): TIoCRegistry; overload;

      class function RegisterSingletonBeanFactory<T>(
        Callback: TSingletonBeanFactoryCallback): TIoCRegistry; overload;

      class function RegisterSingletonBeanFactory<T>(
        const Qualifier: String;
        Callback: TSingletonBeanFactoryCallback): TIoCRegistry; overload;

      class function GetDefaultBeanFactory(): IBeanFactory;
      class constructor Initialize();
      class destructor Unitialize();
  end;

  TSingletonBeanContainerHolder = class
    strict private
      class var _SingletonLock: TMREWSync;
      class var _SingletonBeanContainer: TSessionBeanContainer;
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
  FBeanFactory := BeanFactory;
end;

function TSessionBeanContainer.GetScoped<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
  lBeanFactoryContext: TScopedBeanFactoryContext;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBeanFactoryContext := TScopedBeanFactoryContext.Create(Self);
    try
      lBean := FBeanFactory.CreateBean(lIdentity, lBeanFactoryContext);
      FScopedTable.AddOrSetValue(lIdentity, lBean);
    finally
      lBeanFactoryContext.Free();
    end;
  end;

  Result := lBean.Unwrap<T>();
end;

procedure TSessionBeanContainer.InjectScoped<T>(const Qualifier: String; const Thing: T);
var
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);
  TryInjectScoped(lIdentity, TBean.Wrap(TValue.From<T>(Thing)));
end;

function TSessionBeanContainer.GetScoped<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
  lBeanFactoryContext: TScopedBeanFactoryContext;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBeanFactoryContext := TScopedBeanFactoryContext.Create(Self);
    try
      lBean := FBeanFactory.CreateBean(lIdentity, lBeanFactoryContext);
      FScopedTable.AddOrSetValue(lIdentity, lBean);
    finally
      lBeanFactoryContext.Free();
    end;
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetTransient<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
  lBeanFactoryContext: TScopedBeanFactoryContext;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  lBeanFactoryContext := TScopedBeanFactoryContext.Create(Self);
  try
    lBean := FBeanFactory.CreateBean(lIdentity, lBeanFactoryContext);
    Result := lBean.Unwrap<T>();
  finally
    lBeanFactoryContext.Free();
  end;
end;

function TSessionBeanContainer.GetTransient<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
  lBeanFactoryContext: TScopedBeanFactoryContext;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  lBeanFactoryContext := TScopedBeanFactoryContext.Create(Self);
  try
    lBean := FBeanFactory.CreateBean(lIdentity, lBeanFactoryContext);
    Result := lBean.Unwrap<T>();
  finally
    lBeanFactoryContext.Free();
  end;
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

function TSessionBeanContainer.TryInjectScoped(const Identity: String; const Bean: TBean): Boolean;
begin
  FScopedTable.AddOrSetValue(Identity, Bean);
  Result := True;
end;

function TSessionBeanContainer.TryGetAny(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := True;

  if TryGetScoped(Identity, Bean) then
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

destructor TSessionBeanContainer.Destroy();
begin
  FreeAndNil(FScopedTable);
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
var
  lBeanFactoryContext: TSingletonBeanFactoryContext;
begin
  _SingletonLock.BeginRead();
  try
    if _SingletonBeanContainer.TryGetScoped(Identity, Bean) then
    begin
      Result := True;
      Exit;
    end;
  finally
    _SingletonLock.EndRead();
  end;

  _SingletonLock.BeginWrite();
  try
    if _SingletonBeanContainer.TryGetScoped(Identity, Bean) then
    begin
      Result := True;
      Exit;
    end;

    lBeanFactoryContext := TSingletonBeanFactoryContext.Create(_SingletonBeanContainer);
    try
      Bean := TIoCRegistry.GetDefaultBeanFactory().CreateSingletonBean(Identity, lBeanFactoryContext);
      Result := _SingletonBeanContainer.TryInjectScoped(Identity, Bean);
    finally
      lBeanFactoryContext.Free();
    end;
  finally
    _SingletonLock.EndWrite();
  end;
end;

class destructor TSingletonBeanContainerHolder.Unitialize();
begin
  FreeAndNil(_SingletonBeanContainer);
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
    FValue.ExtractRawData(@Result);
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

      lCastedValue.ExtractRawData(@Result);
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

function TBean.GetTypeInfo(): PTypeInfo;
begin
  Result := FValue.TypeInfo;
end;

class operator TBean.Finalize(var Dest: TBean);
begin
  Dest.Close();
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

class function TIoCRegistry.RegisterSingletonBeanFactory<T>(
  const Qualifier: String;
  Callback: TSingletonBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TSingletonBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  lDefinition.Interceptors := [];
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := Qualifier;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterSingletonBeanFactoryCallback(lIdentity, lDefinition);
end;

class function TIoCRegistry.RegisterSingletonBeanFactory<T>(
  Callback: TSingletonBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TSingletonBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  lDefinition.Interceptors := [];
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := EmptyStr;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterSingletonBeanFactoryCallback(lIdentity, lDefinition);
end;

class function TIoCRegistry.RegisterScopedBeanFactory<T>(
  const Qualifier: String;
  Callback: TScopedBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  lDefinition.Interceptors := [];
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := Qualifier;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterScopedBeanFactoryCallback(lIdentity, lDefinition);
end;

class function TIoCRegistry.RegisterScopedBeanFactory<T>(
  Callback: TScopedBeanFactoryCallback): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  lDefinition.Interceptors := [];
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := EmptyStr;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterScopedBeanFactoryCallback(lIdentity, lDefinition);
end;

class function TIoCRegistry.RegisterScopedBeanFactory<T>(
  Callback: TScopedBeanFactoryCallback;
  const Interceptors: TArray<IInterceptor>): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  lDefinition.Interceptors := Interceptors;
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := EmptyStr;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterScopedBeanFactoryCallback(lIdentity, lDefinition);
end;

class function TIoCRegistry.RegisterScopedBeanFactory<T>(
  const Qualifier: String;
  Callback: TScopedBeanFactoryCallback;
  const Interceptors: TArray<IInterceptor>): TIoCRegistry;
var
  lIdentity: String;
  lDefinition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  lDefinition.Interceptors := Interceptors;
  lDefinition.Callback := Callback;
  lDefinition.Qualifier := Qualifier;
  lDefinition.TypeInfo := TypeInfo(T);

  (_DefaultBeanFactory as TCallbackBeanFactory)
      .RegisterScopedBeanFactoryCallback(lIdentity, lDefinition);
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
  FScopedBeanFactoryDefinitions :=
    TDictionary<String, TBeanFactoryDefinition<TScopedBeanFactoryCallback>>.Create();

  FSingletonBeanFactoryDefinitions :=
    TDictionary<String, TBeanFactoryDefinition<TSingletonBeanFactoryCallback>>.Create();
end;

function TCallbackBeanFactory.CreateBean(const Identity: String; const Ctx: TScopedBeanFactoryContext): TBean;
var
  lInstantiatedBean: TBean;
  lDefinition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>;
begin
  if not FScopedBeanFactoryDefinitions.TryGetValue(Identity, lDefinition) then
    raise EBeanException.CreateFmt('Failed to create bean. Unable to resolve a callback for : %s', [Identity]);


  lInstantiatedBean := TBean.Wrap(lDefinition.Callback(Ctx));

  if not lDefinition.HasInterception() then
  begin
    Result := lInstantiatedBean;
    Exit;
  end;

  try
    TBeanFactoryProxifier.ProxyBean(lInstantiatedBean, lDefinition.Interceptors, lDefinition.TypeInfo, Result);
  except
    lInstantiatedBean.Close();
    raise;
  end;
end;

function TCallbackBeanFactory.CreateSingletonBean(const Identity: String; const Ctx: TSingletonBeanFactoryContext): TBean;
var
  lInstantiatedBean: TBean;
  lDefinition: TBeanFactoryDefinition<TSingletonBeanFactoryCallback>;
begin
  if not FSingletonBeanFactoryDefinitions.TryGetValue(Identity, lDefinition) then
    raise EBeanException.CreateFmt('Failed to create singleton bean. Unable to resolve a callback for : %s', [Identity]);

  lInstantiatedBean := TBean.Wrap(lDefinition.Callback(Ctx));

  if not lDefinition.HasInterception() then
  begin
    Result := lInstantiatedBean;
    Exit;
  end;

  try
    TBeanFactoryProxifier.ProxyBean(lInstantiatedBean, lDefinition.Interceptors, lDefinition.TypeInfo, Result);
  except
    lInstantiatedBean.Close();
    raise;
  end;
end;

procedure TCallbackBeanFactory.RegisterScopedBeanFactoryCallback(
  const Identity: String;
  const Definition: TBeanFactoryDefinition<TScopedBeanFactoryCallback>);
begin
  FScopedBeanFactoryDefinitions.AddOrSetValue(Identity, Definition);
end;

procedure TCallbackBeanFactory.RegisterSingletonBeanFactoryCallback(
  const Identity: String;
  const Definition: TBeanFactoryDefinition<TSingletonBeanFactoryCallback>);
begin
  FSingletonBeanFactoryDefinitions.AddOrSetValue(Identity, Definition);
end;

destructor TCallbackBeanFactory.Destroy();
begin
  FreeAndNil(FScopedBeanFactoryDefinitions);
  FreeAndNil(FSingletonBeanFactoryDefinitions);
  inherited;
end;

{$ENDREGION}

{ TAbstractBeanFactoryContext }

constructor TAbstractBeanFactoryContext.Create(const BeanContainer: TSessionBeanContainer);
begin
  FBeanContainer := BeanContainer;
end;

{ TScopedBeanFactoryContext }

function TScopedBeanFactoryContext.Scoped<T>(): T;
begin
  Result := Container.GetScoped<T>();
end;

function TScopedBeanFactoryContext.Singleton<T>(): T;
begin
  Result := Container.GetSingleton<T>();
end;

function TScopedBeanFactoryContext.Transient<T>(): T;
begin
  Result := Container.GetTransient<T>();
end;

{ TSingletonBeanFactoryContext }

function TSingletonBeanFactoryContext.Singleton<T>(): T;
begin
  Result := Container.GetSingleton<T>();
end;


{ TBeanFactoryDefinition<C> }

function TBeanFactoryDefinition<C>.HasInterception(): Boolean;
begin
  Result := Length(Interceptors) > 0;
end;

{ TBeanFactoryProxifier }

class procedure TBeanFactoryProxifier.ProxyBean(
  const WrappedBean: TBean;
  const Interceptors: TArray<IInterceptor>;
  const InterfaceTypeInfo: PTypeInfo;
  out ProxifiedBean: TBean);
var
  lProxyIntf: TValue;
begin
  lProxyIntf := WrappedBean.Value.Cast(InterfaceTypeInfo, False);
  lProxyIntf := TProxy.CreateProxyFor(lProxyIntf, InterfaceTypeInfo, Interceptors);
  ProxifiedBean := TBean.Wrap(lProxyIntf);
end;

end.
