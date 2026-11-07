//! Thin author macros for `pl-agent-tool`.

use proc_macro::TokenStream;
use proc_macro_crate::{FoundCrate, crate_name};
use proc_macro2::{Span, TokenStream as TokenStream2, TokenTree};
use quote::{ToTokens, format_ident, quote};
use syn::{
    Attribute, Error, FnArg, GenericArgument, ImplItem, ImplItemFn, Item, ItemImpl, ItemStruct,
    Lit, LitStr, Meta, MetaNameValue, Path, PathArguments, ReturnType, Token, Type, parse::Parser,
    parse_quote, punctuated::Punctuated,
};

const FACADE_PACKAGE: &str = "pl-agent-tool";

#[proc_macro_attribute]
pub fn tool_args(attributes: TokenStream, item: TokenStream) -> TokenStream {
    expand_tool_args(attributes.into(), item.into())
        .unwrap_or_else(Error::into_compile_error)
        .into()
}

#[proc_macro_attribute]
pub fn tool(attributes: TokenStream, item: TokenStream) -> TokenStream {
    expand_tool(attributes.into(), item.into())
        .unwrap_or_else(Error::into_compile_error)
        .into()
}

#[derive(Default)]
struct ToolArgsOptions {
    facade: Option<LitStr>,
}

#[derive(Default)]
struct ToolOptions {
    name: Option<LitStr>,
    description: Option<LitStr>,
    facade: Option<LitStr>,
}

fn expand_tool_args(attributes: TokenStream2, item: TokenStream2) -> syn::Result<TokenStream2> {
    let options = parse_tool_args_options(attributes)?;
    let mut item = match syn::parse2::<Item>(item)? {
        Item::Struct(item) => item,
        other => {
            return Err(Error::new_spanned(
                other,
                "`#[tool_args]` only supports structs with named fields",
            ));
        }
    };

    if !matches!(item.fields, syn::Fields::Named(_)) {
        return Err(Error::new_spanned(
            &item.fields,
            "`#[tool_args]` only supports structs with named fields",
        ));
    }
    reject_existing_derive(&item, "Deserialize")?;
    reject_existing_derive(&item, "JsonSchema")?;
    reject_crate_attribute(&item.attrs, "serde")?;
    reject_crate_attribute(&item.attrs, "schemars")?;

    let facade = resolve_facade(options.facade.as_ref())?;
    let serde_path = facade_support_path(&facade, "serde");
    let schemars_path = facade_support_path(&facade, "schemars");
    let serde_crate = LitStr::new(&path_string(&serde_path), Span::call_site());
    let schemars_crate = LitStr::new(&path_string(&schemars_path), Span::call_site());
    let derive: Attribute = parse_quote!(
        #[derive(
            #serde_path::Deserialize,
            #schemars_path::JsonSchema
        )]
    );
    let serde_attribute: Attribute = parse_quote!(#[serde(crate = #serde_crate)]);
    let schemars_attribute: Attribute = parse_quote!(#[schemars(crate = #schemars_crate)]);

    item.attrs.insert(0, schemars_attribute);
    item.attrs.insert(0, serde_attribute);
    item.attrs.insert(0, derive);
    Ok(quote!(#item))
}

fn expand_tool(attributes: TokenStream2, item: TokenStream2) -> syn::Result<TokenStream2> {
    let options = parse_tool_options(attributes)?;
    let item_impl = match syn::parse2::<Item>(item)? {
        Item::Impl(item) if item.trait_.is_none() => item,
        Item::Impl(item) => {
            return Err(Error::new_spanned(
                &item.trait_.as_ref().expect("checked above").1,
                "`#[tool]` only supports inherent impl blocks, not trait impls",
            ));
        }
        other => {
            return Err(Error::new_spanned(
                other,
                "`#[tool]` only supports inherent impl blocks",
            ));
        }
    };

    let name = options
        .name
        .ok_or_else(|| Error::new(Span::call_site(), "`#[tool]` requires `name = \"...\"`"))?;
    let execute =
        find_method(&item_impl, "execute", true)?.expect("required method was checked by helper");
    let execute_signature = validate_execute(execute)?;
    let close = find_method(&item_impl, "close", false)?;
    if let Some(close) = close {
        validate_close(close, &execute_signature.error)?;
    }

    let description = options
        .description
        .unwrap_or_else(|| doc_description(&execute.attrs));
    let facade = resolve_facade(options.facade.as_ref())?;
    let trait_path: Path = parse_quote!(#facade::typed::TypedTool);
    let args = execute_signature.args;
    let context = execute_signature.context;
    let output = execute_signature.output;
    let error = execute_signature.error;
    let self_ty = &item_impl.self_ty;
    let (impl_generics, _, where_clause) = item_impl.generics.split_for_impl();
    let close_forwarder = close.map(|_| {
        quote! {
            fn close(
                &self,
            ) -> impl ::core::future::Future<
                Output = ::core::result::Result<(), Self::Error>
            > + ::core::marker::Send {
                <#self_ty>::close(self)
            }
        }
    });

    Ok(quote! {
        #item_impl

        impl #impl_generics #trait_path for #self_ty #where_clause {
            const NAME: &'static str = #name;
            const DESCRIPTION: &'static str = #description;

            type Args = #args;
            type Context = #context;
            type Output = #output;
            type Error = #error;

            fn execute(
                &self,
                args: Self::Args,
                context: Self::Context,
            ) -> impl ::core::future::Future<
                Output = ::core::result::Result<Self::Output, Self::Error>
            > + ::core::marker::Send {
                <#self_ty>::execute(self, args, context)
            }

            #close_forwarder
        }
    })
}

fn parse_tool_args_options(tokens: TokenStream2) -> syn::Result<ToolArgsOptions> {
    let mut options = ToolArgsOptions::default();
    for argument in parse_attribute_arguments(tokens)? {
        if argument.path.is_ident("crate") {
            set_once(&mut options.facade, string_value(argument)?, "crate")?;
        } else {
            return Err(Error::new_spanned(
                argument.path,
                "unsupported `tool_args` attribute; expected `crate = \"...\"`",
            ));
        }
    }
    Ok(options)
}

fn parse_tool_options(tokens: TokenStream2) -> syn::Result<ToolOptions> {
    let mut options = ToolOptions::default();
    for argument in parse_attribute_arguments(tokens)? {
        if argument.path.is_ident("name") {
            set_once(&mut options.name, string_value(argument)?, "name")?;
        } else if argument.path.is_ident("description") {
            set_once(
                &mut options.description,
                string_value(argument)?,
                "description",
            )?;
        } else if argument.path.is_ident("crate") {
            set_once(&mut options.facade, string_value(argument)?, "crate")?;
        } else {
            return Err(Error::new_spanned(
                argument.path,
                "unsupported `tool` attribute; expected `name`, `description`, or `crate`",
            ));
        }
    }
    Ok(options)
}

fn parse_attribute_arguments(
    tokens: TokenStream2,
) -> syn::Result<Punctuated<MetaNameValue, Token![,]>> {
    Punctuated::<MetaNameValue, Token![,]>::parse_terminated.parse2(tokens)
}

fn string_value(argument: MetaNameValue) -> syn::Result<LitStr> {
    match argument.value {
        syn::Expr::Lit(expression) => match expression.lit {
            Lit::Str(value) => Ok(value),
            other => Err(Error::new_spanned(other, "expected a string literal")),
        },
        other => Err(Error::new_spanned(other, "expected a string literal")),
    }
}

fn set_once(slot: &mut Option<LitStr>, value: LitStr, name: &str) -> syn::Result<()> {
    if slot.is_some() {
        return Err(Error::new(
            value.span(),
            format!("duplicate `{name}` attribute"),
        ));
    }
    *slot = Some(value);
    Ok(())
}

fn resolve_facade(explicit: Option<&LitStr>) -> syn::Result<Path> {
    if let Some(explicit) = explicit {
        return explicit
            .parse()
            .map_err(|_| Error::new(explicit.span(), "`crate` must name a valid Rust crate path"));
    }

    match crate_name(FACADE_PACKAGE) {
        Ok(FoundCrate::Itself) => Ok(parse_quote!(::pl_agent_tool)),
        Ok(FoundCrate::Name(name)) => {
            let identifier = format_ident!("{}", name);
            Ok(parse_quote!(::#identifier))
        }
        Err(error) => Err(Error::new(
            Span::call_site(),
            format!(
                "could not find `{FACADE_PACKAGE}` in dependencies; use `crate = \"...\"`: {error}"
            ),
        )),
    }
}

fn facade_support_path(facade: &Path, support_crate: &str) -> Path {
    let support_crate = format_ident!("{support_crate}");
    parse_quote!(#facade::__macro_support::#support_crate)
}

fn path_string(path: &Path) -> String {
    path.to_token_stream().to_string().replace(' ', "")
}

fn reject_existing_derive(item: &ItemStruct, derive_name: &str) -> syn::Result<()> {
    for attribute in &item.attrs {
        if !attribute.path().is_ident("derive") {
            continue;
        }
        let derives = attribute.parse_args_with(Punctuated::<Path, Token![,]>::parse_terminated)?;
        if let Some(derive) = derives.iter().find(|path| {
            path.segments
                .last()
                .is_some_and(|segment| segment.ident == derive_name)
        }) {
            return Err(Error::new_spanned(
                derive,
                format!(
                    "`#[tool_args]` already derives `{derive_name}`; remove the duplicate derive"
                ),
            ));
        }
    }
    Ok(())
}

fn reject_crate_attribute(attributes: &[Attribute], attribute_name: &str) -> syn::Result<()> {
    for attribute in attributes {
        if !attribute.path().is_ident(attribute_name) {
            continue;
        }
        let Meta::List(list) = &attribute.meta else {
            continue;
        };
        if has_top_level_crate_argument(list.tokens.clone()) {
            return Err(Error::new_spanned(
                attribute,
                format!(
                    "`#[tool_args]` sets `{attribute_name}(crate = ...)`; remove the conflicting crate attribute"
                ),
            ));
        }
    }
    Ok(())
}

fn has_top_level_crate_argument(tokens: TokenStream2) -> bool {
    let mut at_argument_start = true;
    for token in tokens {
        match token {
            TokenTree::Ident(identifier) if at_argument_start => {
                if identifier == "crate" {
                    return true;
                }
                at_argument_start = false;
            }
            TokenTree::Punct(punctuation) if punctuation.as_char() == ',' => {
                at_argument_start = true;
            }
            _ if at_argument_start => {}
            _ => at_argument_start = false,
        }
    }
    false
}

fn find_method<'a>(
    item_impl: &'a ItemImpl,
    name: &str,
    required: bool,
) -> syn::Result<Option<&'a ImplItemFn>> {
    let methods = item_impl
        .items
        .iter()
        .filter_map(|item| match item {
            ImplItem::Fn(method) if method.sig.ident == name => Some(method),
            _ => None,
        })
        .collect::<Vec<_>>();

    match methods.as_slice() {
        [method] => Ok(Some(*method)),
        [] if required => Err(Error::new_spanned(
            &item_impl.self_ty,
            format!("`#[tool]` requires one `async fn {name}` method"),
        )),
        [] => Ok(None),
        _ => Err(Error::new_spanned(
            &methods[1].sig.ident,
            format!("`#[tool]` found more than one `{name}` method"),
        )),
    }
}

struct ExecuteSignature {
    args: Type,
    context: Type,
    output: Type,
    error: Type,
}

fn validate_execute(method: &ImplItemFn) -> syn::Result<ExecuteSignature> {
    validate_common_method(method, "execute")?;
    if method.sig.inputs.len() != 3 {
        return Err(Error::new_spanned(
            &method.sig.inputs,
            "`execute` must have exactly `&self`, owned args, and owned context parameters",
        ));
    }
    validate_receiver(method.sig.inputs.first().expect("length checked"))?;

    let args = owned_parameter_type(
        method.sig.inputs.iter().nth(1).expect("length checked"),
        "args",
    )?;
    let context = owned_parameter_type(
        method.sig.inputs.iter().nth(2).expect("length checked"),
        "context",
    )?;
    let (output, error) = result_types(&method.sig.output, "`execute`")?;
    Ok(ExecuteSignature {
        args,
        context,
        output,
        error,
    })
}

fn validate_close(method: &ImplItemFn, execute_error: &Type) -> syn::Result<()> {
    validate_common_method(method, "close")?;
    if method.sig.inputs.len() != 1 {
        return Err(Error::new_spanned(
            &method.sig.inputs,
            "`close` must have exactly one `&self` receiver",
        ));
    }
    validate_receiver(method.sig.inputs.first().expect("length checked"))?;
    let (output, close_error) = result_types(&method.sig.output, "`close`")?;
    if !matches!(strip_type_wrappers(&output), Type::Tuple(tuple) if tuple.elems.is_empty()) {
        return Err(Error::new_spanned(
            output,
            "`close` must return `Result<(), E>`",
        ));
    }
    if path_string_from_type(&close_error) != path_string_from_type(execute_error) {
        return Err(Error::new_spanned(
            close_error,
            "`close` must use the same error type as `execute`",
        ));
    }
    Ok(())
}

fn validate_common_method(method: &ImplItemFn, name: &str) -> syn::Result<()> {
    if method.sig.asyncness.is_none() {
        return Err(Error::new_spanned(
            &method.sig,
            format!("`{name}` must be `async`"),
        ));
    }
    if !method.sig.generics.params.is_empty() || method.sig.generics.where_clause.is_some() {
        return Err(Error::new_spanned(
            &method.sig.generics,
            format!("`{name}` must not declare method generics"),
        ));
    }
    if method.sig.constness.is_some()
        || method.sig.unsafety.is_some()
        || method.sig.abi.is_some()
        || method.sig.variadic.is_some()
    {
        return Err(Error::new_spanned(
            &method.sig,
            format!("`{name}` must be an ordinary async Rust method"),
        ));
    }
    Ok(())
}

fn validate_receiver(argument: &FnArg) -> syn::Result<()> {
    let FnArg::Receiver(receiver) = argument else {
        return Err(Error::new_spanned(
            argument,
            "the first parameter must be `&self`",
        ));
    };
    let plain_reference = receiver.colon_token.is_none()
        && receiver.mutability.is_none()
        && receiver
            .reference
            .as_ref()
            .is_some_and(|(_, lifetime)| lifetime.is_none());
    if !plain_reference {
        return Err(Error::new_spanned(
            receiver,
            "the receiver must be exactly `&self`",
        ));
    }
    Ok(())
}

fn owned_parameter_type(argument: &FnArg, parameter_name: &str) -> syn::Result<Type> {
    let FnArg::Typed(argument) = argument else {
        return Err(Error::new_spanned(
            argument,
            format!("`{parameter_name}` must be an owned typed parameter"),
        ));
    };
    if matches!(strip_type_wrappers(&argument.ty), Type::Reference(_)) {
        return Err(Error::new_spanned(
            &argument.ty,
            format!("`{parameter_name}` must be owned, not directly borrowed"),
        ));
    }
    Ok((*argument.ty).clone())
}

fn result_types(output: &ReturnType, method_name: &str) -> syn::Result<(Type, Type)> {
    let ReturnType::Type(_, ty) = output else {
        return Err(Error::new_spanned(
            output,
            format!("{method_name} must return `Result<O, E>`"),
        ));
    };
    let Type::Path(result) = strip_type_wrappers(ty) else {
        return Err(Error::new_spanned(
            ty,
            format!("{method_name} must return `Result<O, E>` directly, not a type alias"),
        ));
    };
    if result.qself.is_some() || !is_supported_result_path(&result.path) {
        return Err(Error::new_spanned(
            ty,
            format!("{method_name} must return `Result<O, E>` directly, not a type alias"),
        ));
    }
    let PathArguments::AngleBracketed(arguments) = &result
        .path
        .segments
        .last()
        .expect("non-empty path")
        .arguments
    else {
        return Err(Error::new_spanned(
            ty,
            format!("{method_name} must return `Result<O, E>`"),
        ));
    };
    let types = arguments
        .args
        .iter()
        .filter_map(|argument| match argument {
            GenericArgument::Type(ty) => Some(ty.clone()),
            _ => None,
        })
        .collect::<Vec<_>>();
    if arguments.args.len() != 2 || types.len() != 2 {
        return Err(Error::new_spanned(
            arguments,
            format!("{method_name} must return `Result<O, E>`"),
        ));
    }
    Ok((types[0].clone(), types[1].clone()))
}

fn is_supported_result_path(path: &Path) -> bool {
    let segments = path
        .segments
        .iter()
        .map(|segment| segment.ident.to_string())
        .collect::<Vec<_>>();
    match segments.as_slice() {
        [result] => result == "Result",
        [root, module, result] => {
            (root == "std" || root == "core") && module == "result" && result == "Result"
        }
        _ => false,
    }
}

fn strip_type_wrappers(mut ty: &Type) -> &Type {
    loop {
        ty = match ty {
            Type::Group(group) => &group.elem,
            Type::Paren(paren) => &paren.elem,
            _ => return ty,
        };
    }
}

fn path_string_from_type(ty: &Type) -> String {
    strip_type_wrappers(ty)
        .to_token_stream()
        .to_string()
        .replace(' ', "")
}

fn doc_description(attributes: &[Attribute]) -> LitStr {
    let lines = attributes
        .iter()
        .filter(|attribute| attribute.path().is_ident("doc"))
        .filter_map(|attribute| match &attribute.meta {
            Meta::NameValue(value) => match &value.value {
                syn::Expr::Lit(expression) => match &expression.lit {
                    Lit::Str(value) => Some(value.value().trim().to_owned()),
                    _ => None,
                },
                _ => None,
            },
            _ => None,
        })
        .collect::<Vec<_>>();
    LitStr::new(&lines.join("\n"), Span::call_site())
}

#[cfg(test)]
mod tests {
    use super::*;
    use quote::quote;

    fn error_text(result: syn::Result<TokenStream2>) -> String {
        result.expect_err("expansion should fail").to_string()
    }

    #[test]
    fn tool_args_preserves_struct_and_routes_derives_through_facade() {
        let expanded = expand_tool_args(
            quote!(crate = "tool_api"),
            quote! {
                /// Arguments.
                #[serde(rename_all = "camelCase")]
                #[schemars(extend("x-origin" = "author"))]
                pub struct Args<T>
                where
                    T: Clone,
                {
                    #[serde(flatten)]
                    pub values: T,
                }
            },
        )
        .expect("tool_args should expand");
        let item: ItemStruct = syn::parse2(expanded).expect("expanded struct should parse");

        assert_eq!(item.vis.to_token_stream().to_string(), "pub");
        assert_eq!(item.generics.params.len(), 1);
        let attributes = item
            .attrs
            .iter()
            .map(ToTokens::to_token_stream)
            .map(|tokens| tokens.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        assert!(attributes.contains("tool_api :: __macro_support :: serde :: Deserialize"));
        assert!(attributes.contains("tool_api :: __macro_support :: schemars :: JsonSchema"));
        assert!(attributes.contains("serde (crate = \"tool_api::__macro_support::serde\")"));
        assert!(attributes.contains("schemars (crate = \"tool_api::__macro_support::schemars\")"));
        assert!(attributes.contains("serde (rename_all = \"camelCase\")"));
        assert!(attributes.contains("schemars (extend (\"x-origin\" = \"author\"))"));
    }

    #[test]
    fn tool_args_rejects_unsupported_shapes_and_conflicts() {
        assert!(
            error_text(expand_tool_args(
                TokenStream2::new(),
                quote!(
                    struct Args(u64);
                )
            ))
            .contains("named fields")
        );
        assert!(
            error_text(expand_tool_args(
                TokenStream2::new(),
                quote!(
                    #[derive(serde::Deserialize)]
                    struct Args {
                        value: u64,
                    }
                )
            ))
            .contains("already derives `Deserialize`")
        );
        assert!(
            error_text(expand_tool_args(
                TokenStream2::new(),
                quote!(
                    #[schemars(crate = "other")]
                    struct Args {
                        value: u64,
                    }
                )
            ))
            .contains("conflicting crate attribute")
        );
    }

    #[test]
    fn tool_forwards_generic_inherent_methods_without_appending_generics() {
        let expanded = expand_tool(
            quote!(name = "lookup", crate = "tool_api"),
            quote! {
                impl<T> Lookup<T>
                where
                    T: Send + Sync + 'static,
                {
                    /// Looks up a value.
                    /// Returns the owned result.
                    async fn execute(
                        &self,
                        args: Args<T>,
                        context: Context,
                    ) -> core::result::Result<Output<T>, Error> {
                        todo!()
                    }

                    async fn close(&self) -> std::result::Result<(), Error> {
                        todo!()
                    }
                }
            },
        )
        .expect("tool should expand");
        let file: syn::File = syn::parse2(expanded).expect("expanded impls should parse");
        let generated = match &file.items[1] {
            Item::Impl(item) => item,
            other => panic!("expected generated impl, got {}", other.to_token_stream()),
        };

        assert_eq!(generated.generics.params.len(), 1);
        assert_eq!(
            generated.self_ty.to_token_stream().to_string(),
            "Lookup < T >"
        );
        assert_eq!(
            generated
                .trait_
                .as_ref()
                .expect("trait impl")
                .1
                .to_token_stream()
                .to_string(),
            "tool_api :: typed :: TypedTool"
        );
        let generated_tokens = generated.to_token_stream().to_string();
        assert!(generated_tokens.contains("< Lookup < T > > :: execute (self , args , context)"));
        assert!(generated_tokens.contains("< Lookup < T > > :: close (self)"));
        assert!(generated_tokens.contains(
            "const DESCRIPTION : & 'static str = \"Looks up a value.\\nReturns the owned result.\""
        ));
    }

    #[test]
    fn tool_rejects_invalid_method_shapes() {
        let cases = [
            (
                quote! {
                    impl Tool {
                        fn execute(&self, args: Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                },
                "must be `async`",
            ),
            (
                quote! {
                    impl Tool {
                        async fn execute<T>(&self, args: T, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                },
                "must not declare method generics",
            ),
            (
                quote! {
                    impl Tool {
                        async fn execute(&mut self, args: Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                },
                "exactly `&self`",
            ),
            (
                quote! {
                    impl Tool {
                        async fn execute(&self, args: &Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                },
                "must be owned",
            ),
            (
                quote! {
                    impl Tool {
                        async fn execute(&self, args: Args, context: ()) -> Alias {
                            todo!()
                        }
                    }
                },
                "not a type alias",
            ),
            (
                quote! {
                    impl Tool {
                        async fn execute(&self, args: Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                        async fn close(&self) -> Result<(), OtherError> {
                            todo!()
                        }
                    }
                },
                "same error type",
            ),
        ];

        for (item, expected) in cases {
            let error = error_text(expand_tool(quote!(name = "tool"), item));
            assert!(error.contains(expected), "unexpected error: {error}");
        }
    }

    #[test]
    fn tool_requires_name_and_an_inherent_impl() {
        assert!(
            error_text(expand_tool(
                TokenStream2::new(),
                quote! {
                    impl Tool {
                        async fn execute(&self, args: Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                }
            ))
            .contains("requires `name")
        );
        assert!(
            error_text(expand_tool(
                quote!(name = "tool"),
                quote! {
                    impl Trait for Tool {
                        async fn execute(&self, args: Args, context: ()) -> Result<Out, Error> {
                            todo!()
                        }
                    }
                }
            ))
            .contains("not trait impls")
        );
    }
}
