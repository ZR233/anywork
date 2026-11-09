use pl_skill_core::SkillCoreError;
use std::path::PathBuf;

pub fn validate_name(name: &str) -> Result<(), SkillCoreError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(SkillCoreError::new("skill name must not be empty"));
    }
    if name.chars().count() > 64 {
        return Err(SkillCoreError::new(
            "skill name must be at most 64 characters",
        ));
    }
    if !name
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
    {
        return Err(SkillCoreError::new(format!(
            "skill name contains unsupported characters: {name}"
        )));
    }
    Ok(())
}
pub fn category_path(category: &str) -> Result<PathBuf, SkillCoreError> {
    let path = pl_skill_core::safe_relative_path(category.trim())?;
    if path.components().any(|part| {
        !part.as_os_str().to_str().is_some_and(|part| {
            part.chars()
                .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
        })
    }) {
        return Err(SkillCoreError::new(format!(
            "skill category contains unsupported characters: {category}"
        )));
    }
    Ok(path)
}
pub fn validate_document(
    text: &str,
    expected: Option<&str>,
) -> Result<pl_skill_core::SkillFrontmatter, SkillCoreError> {
    let mut metadata = pl_skill_core::parse_skill_document(text)?.frontmatter;
    validate_name(&metadata.name)?;
    if let Some(expected) = expected
        && !metadata.name.eq_ignore_ascii_case(expected)
    {
        return Err(SkillCoreError::new(format!(
            "skill frontmatter name '{}' does not match target '{expected}'",
            metadata.name
        )));
    }
    metadata.description = metadata.description.trim().into();
    if metadata.description.is_empty() {
        return Err(SkillCoreError::new("skill description must not be empty"));
    }
    if metadata.description.chars().count() > 1024 {
        return Err(SkillCoreError::new(
            "skill description must be at most 1024 characters",
        ));
    }
    if let Some(category) = &metadata.category {
        category_path(category)?;
    }
    metadata.category = metadata
        .category
        .map(|category| category.trim().into())
        .filter(|category: &String| !category.is_empty());
    Ok(metadata)
}
