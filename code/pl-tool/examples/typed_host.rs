//! Compileable host registration examples; executable behavior is exercised in `typed_binding`.
#[path = "support/typed_authors.rs"]
mod authors;

fn main() -> Result<(), pl_tool::binding::BindingError> {
    let add = authors::register_add(10)?;
    let finish = authors::register_finish("Result".into())?.with_turn_completion();
    println!("{add:?}\n{finish:?}");
    Ok(())
}
