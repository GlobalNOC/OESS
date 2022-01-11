import React, { useEffect, useState } from "react";

import { getEntities } from "../../api/entities";

import { AutoComplete } from "../generic_components/AutoComplete";


export const EntityAutoComplte = (props) => {
  const [entities, setEntities] = useState([]);

  useEffect(() => {
    try {
      getEntities().then((entities) => {
        console.info(entities);
        setEntities(entities);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails workgroups can't be loaded.
      setEntities([]);
      console.error(error);
    }
  }, []);

  let suggestions = entities.map((e) => {
    return {name: e.name, value: parseInt(e.entity_id)};
  });
  if (props.nullOption) {
    suggestions = [props.nullOption, ...suggestions];
  }

  return (
    <div className="input-group">
      <AutoComplete id={props.id} name={props.name} placeholder="Search by entity" value={props.value} onChange={props.onChange} suggestions={suggestions} style={{borderRadius: "4px 0px 0px 4px"}} />
      <span class="input-group-addon"><span class="glyphicon glyphicon-search" aria-hidden="true"></span></span>
    </div>
  );
};
