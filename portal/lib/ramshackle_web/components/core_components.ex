defmodule RamshackleWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  These are homegrown components with no CSS framework behind them. They
  render semantic HTML and carry no classes. Each component that needs
  styling marks its root with a `data-*` attribute (for example
  `data-flash`), and the matching rules live in
  `assets/css/components.css`. Plain elements such as `<table>`, `<button>`
  and `<input>` are styled in `assets/css/base.css`.

  See [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html)
  for the components Phoenix defines, such as `<.link>` and `<.form>`.
  """
  use Phoenix.Component
  use Gettext, backend: RamshackleWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role="alert"
      data-flash={@kind}
      {@rest}
    >
      <div>
        <div>
          <p :if={@title}><strong>{@title}</strong></p>
          <p>{msg}</p>
        </div>
        <button
          type="button"
          phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
          aria-label={gettext("close")}
        >
          <span aria-hidden="true">&times;</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button, or a link styled as a button when given `href`,
  `navigate` or `patch`.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :variant, :string, default: nil, values: [nil, "primary"]
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link data-button data-variant={@variant} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button data-variant={@variant} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  When there are errors, the control gets `aria-invalid="true"` and an
  `aria-describedby` pointing at the error messages, so assistive
  technology announces them with the control. This needs an `id`, which a
  form field always provides.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" label="Email" />
  <.input id="my-input" name="my-input" label="Name" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assigns
      |> assign_error_ids()
      |> assign_new(:checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div data-field="checkbox">
      <input
        type="hidden"
        name={@name}
        value="false"
        disabled={@rest[:disabled]}
        form={@rest[:form]}
      />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        aria-invalid={@invalid && "true"}
        aria-describedby={@described_by}
        {@rest}
      />
      <label :if={@label} for={@id}>{@label}</label>
      <.field_errors id={@error_id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    assigns = assign_error_ids(assigns)

    ~H"""
    <div data-field>
      <label :if={@label} for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        multiple={@multiple}
        aria-invalid={@invalid && "true"}
        aria-describedby={@described_by}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.field_errors id={@error_id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = assign_error_ids(assigns)

    ~H"""
    <div data-field>
      <label :if={@label} for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        aria-invalid={@invalid && "true"}
        aria-describedby={@described_by}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.field_errors id={@error_id} errors={@errors} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    assigns = assign_error_ids(assigns)

    ~H"""
    <div data-field>
      <label :if={@label} for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        aria-invalid={@invalid && "true"}
        aria-describedby={@described_by}
        {@rest}
      />
      <.field_errors id={@error_id} errors={@errors} />
    </div>
    """
  end

  # Links a control to its error messages for assistive technology.
  defp assign_error_ids(assigns) do
    invalid = assigns.errors != []
    error_id = assigns.id && "#{assigns.id}-errors"

    assign(assigns,
      invalid: invalid,
      error_id: error_id,
      described_by: invalid && error_id
    )
  end

  attr :id, :string, default: nil
  attr :errors, :list, required: true

  defp field_errors(assigns) do
    ~H"""
    <div :if={@errors != []} id={@id} data-field-errors>
      <p :for={msg <- @errors}>{msg}</p>
    </div>
    """
  end

  @doc """
  Renders a page header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header data-page-header>
      <div>
        <h1>{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []}>{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []}>{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table>
      <thead>
        <tr>
          <th :for={col <- @col} scope="col">{col[:label]}</th>
          <th :if={@action != []} scope="col">{gettext("Actions")}</th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td :for={col <- @col} phx-click={@row_click && @row_click.(row)}>
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []}>
            <div data-row-actions>
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a description list of titled items.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl data-list>
      <div :for={item <- @item}>
        <dt>{item.title}</dt>
        <dd>{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  ## JS Commands

  # Entry animation lives in CSS (`@starting-style` on `[data-flash]`), so
  # these commands only toggle visibility and need no transition classes.

  def show(js \\ %JS{}, selector) do
    JS.show(js, to: selector)
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js, to: selector)
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(RamshackleWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(RamshackleWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
