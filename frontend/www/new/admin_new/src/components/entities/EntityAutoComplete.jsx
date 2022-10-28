import React, { useEffect, useState } from "react";
import { useContext } from "react";

import { getEntities } from "../../api/entities";
import { PageContext } from "../../contexts/PageContext";

import { AutoComplete } from "../generic_components/AutoComplete";


export const EntityAutoComplte = (props) => {
  const [entities, setEntities] = useState([]);

  const { workgroup } = useContext(PageContext);

  useEffect(() => {
    try {
      getEntities(workgroup.workgroup_id).then((entities) => {
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
      <span className="input-group-addon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
    </div>
  );
};
