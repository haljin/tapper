defmodule Tapper.Tracer.Supervisor do
  @moduledoc "Supervises `Tapper.Tracer.Server` instances."

  use Supervisor
  require Logger

  alias Tapper.Timestamp

  def start_link(config) do
    Supervisor.start_link(__MODULE__, [config], name: __MODULE__)
  end

  def init([config]) do
    supervise(
      [worker(Tapper.Tracer.Server, [config], restart: :transient)], # template for children, with config as first param
      strategy: :simple_one_for_one # i.e. on demand
    )
  end

  @doc "start tracing server with initial trace info"
  @spec start_tracer(id :: Tapper.Id.t, shared :: boolean, timestamp :: Timestamp.t, opts :: Keyword.t) :: Supervisor.on_start_child()
  def start_tracer(id, shared, timestamp, opts) do

    # NB calls Tapper.Tracer.Server.start_link/5 with our worker init config as first argument (see worker above)
    result = Supervisor.start_child(__MODULE__, [id, shared, self(), timestamp, opts])

    case result do
      {:ok, _child} ->
        result
      _ ->
        Logger.error("Error starting child for #{inspect(result)}")
        result
    end
  end

end
