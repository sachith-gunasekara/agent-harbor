---
name: python-test
description: Best practices and patterns for testing Python applications using pytest, pytest-xdist, and testcontainers. Covers unit testing, integration testing with mocks, and integration testing with real resources.
metadata:
  author: Deerhide
  version: 1.0.0
---

# Python Testing

## When to use this skill?

- Use this skill when writing unit tests for Python applications.
- Use this skill when writing integration tests with mocked infrastructure.
- Use this skill when writing integration tests with real resources using testcontainers.
- Use this skill when setting up pytest configuration and fixtures.
- Use this skill when running tests in parallel with pytest-xdist.
- Use this skill when following test-driven development (TDD) practices.
- Use this skill when testing FastAPI applications and use cases.

---

## Overview

This skill provides testing patterns for Python applications following a layered testing strategy:

| Test Type | Purpose | Dependencies |
|-----------|---------|--------------|
| **Unit Tests** | Test isolated units of code (functions, classes, methods) | Mocked dependencies |
| **Integration Tests (Mocked)** | Test interaction between components | Mocked infrastructure (databases, APIs) |
| **Integration Tests (Real)** | Validate infrastructure integration | Real resources via testcontainers |

The testing approach follows Clean Architecture principles, using dependency injection to enable easy mocking and isolation of components.

---

## Testing Strategy

### Unit Tests

Test individual components in isolation. All external dependencies are mocked.

- Located in `tests/units/`
- Fast execution, no I/O operations
- Test business logic in domain and application layers
- Mock all repositories, services, and external clients

For detailed patterns, see [Unit Testing](references/unit-testing.md).

### Integration Tests with Mocks

Test interaction between multiple components with mocked infrastructure.

- Located in `tests/integrations/`
- Test API routes with mocked use cases
- Test use cases with mocked repositories
- Validate request/response serialization

For detailed patterns, see [Integration Testing with Mocks](references/integration-testing-mocks.md).

### Integration Tests with Real Resources

Validate infrastructure integration using testcontainers.

- Located in `tests/integrations/`
- Use real databases, message queues, etc.
- Validate repository implementations
- Test database migrations and queries

For detailed patterns, see [Integration Testing with Testcontainers](references/integration-testing-testcontainers.md).

### Fixtures

Use shared fixtures for test data and setup/teardown logic.
For detailed patterns, see [Test Fixtures](references/test-fixtures.md).

---

## Test Structure

```
tests/
|-- __init__.py
|-- conftest.py              # Shared fixtures
|-- fixtures/                # Test data factories
|   |-- __init__.py
|   |-- book_fixtures.py
|-- units/                   # Unit tests
|   |-- __init__.py
|   |-- domain/
|   |-- usecases/
|   |-- services/
|-- integrations/            # Integration tests
|   |-- __init__.py
|   |-- api/
|   |-- persistence/
```

---

## Main Technology Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| **pytest** | >= 8.0.0 | Test framework |
| **pytest-xdist** | >= 3.5.0 | Parallel test execution |
| **pytest-cov** | >= 4.1.0 | Code coverage |
| **pytest-asyncio** | >= 0.23.0 | Async test support |
| **testcontainers** | >= 4.0.0 | Real resource containers |
| **httpx** | >= 0.27.0 | Async HTTP client for API testing (TestClient alternative) |

---

## References

### Skill References

| Document | Description |
|----------|-------------|
| [Unit Testing](references/unit-testing.md) | Patterns for unit testing with mocks |
| [Integration Testing with Mocks](references/integration-testing-mocks.md) | Testing component interaction with mocked infrastructure |
| [Integration Testing with Testcontainers](references/integration-testing-testcontainers.md) | Testing with real resources using containers |
| [Pytest Configuration](references/pytest-configuration.md) | pytest.ini, conftest.py, and fixtures setup |
| [Test Fixtures](references/test-fixtures.md) | Fixture patterns with functional naming and centralized organization |

### Related Skills

| Document | Description |
|----------|-------------|
| [python-architecture](../python-architecture/SKILL.md) | Project structure and architecture patterns |
| [Use Cases Pattern](../python-architecture/references/usecases-pattern.md) | How to test use cases |
| [Dependency Injection](../python-architecture/references/dependency-injection.md) | DI patterns for testability |
| [python](../python/SKILL.md) | Python coding standards |
| [python-lint](../python-lint/SKILL.md) | Code quality checks |
| [fastapi-factory-utilities](../fastapi-factory-utilities/SKILL.md) | Mock utilities for HTTP clients and repositories |

### External References

| Document | Description |
|----------|-------------|
| [pytest Documentation](https://docs.pytest.org/) | Official pytest documentation |
| [pytest-xdist](https://pytest-xdist.readthedocs.io/) | Parallel test execution |
| [testcontainers-python](https://testcontainers-python.readthedocs.io/) | Testcontainers for Python |
| [FastAPI Testing](https://fastapi.tiangolo.com/tutorial/testing/) | Testing FastAPI applications |
