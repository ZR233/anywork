//! A renamed downstream dependency executes the independent author without Anywork.
struct Host;
impl lua::ToolHost for Host {
    fn bindings(&self) -> Vec<lua::Binding> {
        vec![lua::Binding { name: "echo".into(), parallel: true }]
    }
    async fn call(&self, _name: String, arguments: serde_json::Value) -> Result<serde_json::Value, lua::CallFailure> {
        Ok(arguments)
    }
}

#[tokio::test]
async fn independently_consumes_the_lua_author_through_the_shared_handle() {
    let tool = lua::ExecTool::<Host>::new(lua::definition("tools.echo(args)"));
    let handle = pl_agent_tool::ToolHandle::new(tool);
    let result = handle.execute(
        serde_json::json!({"code":"local value=tools.echo({selected=17,hidden='private'}); return value.selected"}).to_string(),
        lua::ExecContext { host: Host, cancellation: Default::default() },
    ).await.unwrap();
    assert_eq!(result.output, "17");
    assert_eq!(result.error, None);
}
