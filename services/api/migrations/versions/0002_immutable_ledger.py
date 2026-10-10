"""Keep the audit ledger immutable, including privileged application mistakes."""

from alembic import op

revision = "0002_immutable_ledger"
down_revision = "600eb2dbb6da"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""CREATE FUNCTION deny_ledger_mutation() RETURNS trigger AS $$
                  BEGIN RAISE EXCEPTION 'ledger entries are immutable'; END;
                  $$ LANGUAGE plpgsql""")
    op.execute("""CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON ledger_entries
                  FOR EACH ROW EXECUTE FUNCTION deny_ledger_mutation()""")


def downgrade():
    op.execute("DROP TRIGGER immutable_ledger ON ledger_entries")
    op.execute("DROP FUNCTION deny_ledger_mutation()")
